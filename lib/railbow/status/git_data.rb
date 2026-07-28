# frozen_string_literal: true

require "date"
require_relative "../git_utils"
require_relative "../multi_db"
require_relative "../params"

module Railbow
  module Status
    # Every git lookup db:migrate:status makes about a migrations directory:
    # who wrote each migration, when it landed on the mainline, which branch
    # introduced it, and what is still uncommitted.
    #
    # One instance per migrations directory. Multi-database runs reuse the
    # instance across databases that share a directory, which is what keeps
    # `git log` from running once per database.
    class GitData
      EMPTY_AUTHORS = {names: {}, emails: {}}.freeze

      attr_reader :migrate_dir, :author_names, :author_emails, :landed_dates,
        :git_email, :git_name, :branch_origins, :uncommitted_files,
        :incoming_merge_files, :merge_source_label

      # migrate_dir is nil when no migration file could be located, in which
      # case every file-scoped lookup is skipped and the accessors stay empty.
      def initialize(migrate_dir:, author_enabled:, diff_enabled:, base_override: "", branch_mask: "")
        @migrate_dir = migrate_dir
        @author_names = {}
        @author_emails = {}
        @landed_dates = {}
        @branch_origins = {}
        @uncommitted_files = Set.new
        @incoming_merge_files = Set.new
        @merge_source_label = nil

        load_authors(author_enabled)
        load_diff(branch_mask, base_override) if diff_enabled && migrate_dir
      end

      # Shares one instance per migrations directory across a multi-database
      # run. Databases that share a directory (shards) or a run that renders
      # several databases would otherwise repeat the same full-history
      # `git log` once per database.
      def self.for(migrate_dir:, **opts)
        cache = Railbow::MultiDb.current&.git_cache
        return new(migrate_dir: migrate_dir, **opts) unless cache

        cache[[migrate_dir, opts]] ||= new(migrate_dir: migrate_dir, **opts)
      end

      # Extracts a display label from a branch name. "auto" uses the built-in
      # ticket pattern; anything else is a regex whose first capture wins.
      def self.apply_branch_mask(branch, branch_mask)
        return branch if branch_mask.empty?
        return Railbow::Params.extract_branch_ticket(branch) if branch_mask == "auto"

        re = begin
          Regexp.new(branch_mask, Regexp::IGNORECASE)
        rescue RegexpError
          return branch
        end
        m = branch.match(re)
        (m && m[1]) ? m[1] : branch
      end

      private

      def apply_branch_mask(branch, branch_mask)
        self.class.apply_branch_mask(branch, branch_mask)
      end

      def load_authors(author_enabled)
        if migrate_dir
          @landed_dates = migration_landed_dates
          if author_enabled
            result = migration_authors
            @author_names = result[:names]
            @author_emails = result[:emails]
          end
        end
        return unless author_enabled

        @git_email = current_git_email
        @git_name = current_git_name
      end

      def load_diff(branch_mask, base_override)
        base_branch = detect_default_branch(base_override)
        @branch_origins = branch_migration_origins(base_branch, branch_mask)
        @incoming_merge_files = incoming_merge_files_from_git
        @merge_source_label = detect_merge_source_label(branch_mask) if @incoming_merge_files.any?
        @uncommitted_files = uncommitted_migration_files

        # Uncommitted files have no commit to attribute, so they belong to
        # whatever branch is checked out right now.
        current_branch = current_branch_name(branch_mask)
        @uncommitted_files.each { |f| @branch_origins[f] ||= current_branch }
      end

      def migration_authors
        output, _status = Railbow::GitUtils.capture2(
          "log", "--format=COMMIT:%aN\t%aE", "--diff-filter=AR", "--name-status", "--", migrate_dir
        )
        return EMPTY_AUTHORS.dup if output.empty?

        names = {}
        emails = {}
        current_name = nil
        current_email = nil
        output.each_line do |line|
          line = line.strip
          if line.start_with?("COMMIT:")
            parts = line.sub("COMMIT:", "").split("\t", 2)
            current_name = parts[0]
            current_email = parts[1]&.downcase
          elsif !line.empty? && current_name
            basename = name_status_basename(line)
            next unless basename
            names[basename] ||= current_name
            emails[basename] ||= current_email
          end
        end
        {names: names, emails: emails}
      end

      # basename => Date the migration first appeared on the mainline (the
      # merge commit date, via --first-parent).
      def migration_landed_dates
        output, _status = Railbow::GitUtils.capture2(
          "log", "--first-parent", "--format=COMMIT:%cI", "--diff-filter=AR", "--name-status", "--", migrate_dir
        )
        return {} if output.empty?

        dates = {}
        current_date = nil
        output.each_line do |line|
          line = line.strip
          if line.start_with?("COMMIT:")
            current_date = begin
              Date.parse(line.sub("COMMIT:", ""))
            rescue Date::Error
              nil
            end
          elsif !line.empty? && current_date
            basename = name_status_basename(line)
            next unless basename
            dates[basename] ||= current_date
          end
        end
        dates
      end

      # --name-status lines are "A\tfilepath" or "Rnnn\told\tnew"; a rename
      # attributes to its destination.
      def name_status_basename(line)
        cols = line.split("\t")
        filepath = cols[0]&.start_with?("R") ? cols[2] : cols[1]
        filepath ? File.basename(filepath) : nil
      end

      def current_git_email
        output, _status = Railbow::GitUtils.capture2("config", "user.email")
        output.strip.downcase
      end

      def current_git_name
        output, _status = Railbow::GitUtils.capture2("config", "user.name")
        output.strip
      end

      def current_branch_name(branch_mask)
        output, status = Railbow::GitUtils.capture2("rev-parse", "--abbrev-ref", "HEAD")
        return "HEAD" unless status.success?

        apply_branch_mask(output.strip, branch_mask)
      end

      def detect_default_branch(override)
        return override if override && !override.empty?

        output, status = Railbow::GitUtils.capture2("symbolic-ref", "refs/remotes/origin/HEAD")
        if status.success?
          branch = output.strip.sub(%r{^refs/remotes/origin/}, "")
          return branch unless branch.empty?
        end

        %w[main master].each do |candidate|
          _, st = Railbow::GitUtils.capture2("rev-parse", "--verify", "refs/heads/#{candidate}")
          return candidate if st.success?
        end

        "main"
      end

      def branch_migration_origins(base_branch, branch_mask)
        merge_base_out, mb_status = Railbow::GitUtils.capture2("merge-base", "HEAD", base_branch)
        return {} unless mb_status.success?

        merge_base = merge_base_out.strip
        diff_out, diff_status = Railbow::GitUtils.capture2(
          "diff", "--name-status", "--diff-filter=AR", merge_base, "HEAD", "--", migrate_dir
        )
        return {} unless diff_status.success?

        files = diff_out.each_line.map { |l|
          cols = l.strip.split("\t")
          cols[0]&.start_with?("R") ? cols[2] : cols[1]
        }.compact.reject(&:empty?)
        origins = {}

        files.each do |filepath|
          basename = File.basename(filepath)
          commit = adding_commit(filepath)
          next unless commit

          branches = branches_containing(commit)
          next if branches.empty?

          best = pick_origin_branch(branches, commit)
          origins[basename] = best ? apply_branch_mask(best, branch_mask) : best
        end

        origins
      end

      def adding_commit(filepath)
        commit_out, cs = Railbow::GitUtils.capture2(
          "log", "--diff-filter=AR", "--format=%H", "-1", "--", filepath
        )
        return nil unless cs.success?

        commit = commit_out.strip
        commit.empty? ? nil : commit
      end

      def branches_containing(commit)
        branches_out, bs = Railbow::GitUtils.capture2(
          "branch", "--contains", commit, "--format=%(refname:short)"
        )
        return [] unless bs.success?

        branches_out.each_line.map(&:strip).reject(&:empty?)
      end

      # Picks the branch that originally introduced the commit.
      # 1. Drop child branches: if A is an ancestor of B, the commit came from A.
      # 2. Among the rest, prefer the branch with the most commits after the
      #    adding commit - it has been active longest since, so it is the
      #    original rather than a newer fork.
      def pick_origin_branch(branches, commit)
        return branches.first if branches.size == 1

        filtered = branches.reject do |b|
          branches.any? do |other|
            next false if other == b
            _, st = Railbow::GitUtils.capture2("merge-base", "--is-ancestor", other, b)
            st.success?
          end
        end
        filtered = branches if filtered.empty?
        return filtered.first if filtered.size == 1

        filtered.max_by do |b|
          count_out, _ = Railbow::GitUtils.capture2("rev-list", "--count", "#{commit}..#{b}")
          count_out.strip.to_i
        end
      end

      def uncommitted_migration_files
        output, status = Railbow::GitUtils.capture2("status", "--porcelain", "--", migrate_dir)
        return Set.new unless status.success?

        result = Set.new
        output.each_line do |line|
          code = line[0..1]

          if code[0] == "R"
            # Rename: "R  old -> new" or "R100 old -> new". Take the destination.
            parts = line[3..].split(" -> ", 2)
            filepath = (parts[1] || parts[0]).strip
          elsif ["??", "A ", "AM", "M "].include?(code)
            filepath = line[3..].strip
          else
            next
          end

          result << File.basename(filepath) unless filepath.empty?
        end

        # During an in-progress merge, files from MERGE_HEAD (e.g. main) show up
        # as staged additions. Exclude them so they are not tagged as ours.
        result - incoming_merge_files_from_git
      end

      def detect_merge_source_label(branch_mask)
        merge_head, _, status = Railbow::GitUtils.capture3("rev-parse", "MERGE_HEAD")
        return nil unless status.success?

        branches_out, _, bs = Railbow::GitUtils.capture3(
          "branch", "--contains", merge_head.strip, "--format=%(refname:short)"
        )
        return nil unless bs.success?

        branches = branches_out.each_line.map(&:strip).reject(&:empty?)
        return nil if branches.empty?

        branch = branches.first if branches.size == 1
        branch ||= branches.find { |b| %w[main master develop].include?(b) }
        branch ||= branches.first

        apply_branch_mask(branch, branch_mask)
      end

      def incoming_merge_files_from_git
        _, _, mh_status = Railbow::GitUtils.capture3("rev-parse", "MERGE_HEAD")
        return Set.new unless mh_status.success?

        output, _, status = Railbow::GitUtils.capture3(
          "diff", "--name-only", "--diff-filter=AR", "HEAD", "MERGE_HEAD", "--", migrate_dir
        )
        return Set.new unless status.success?

        Set.new(output.each_line.map { |l| File.basename(l.strip) }.reject(&:empty?))
      end
    end
  end
end
