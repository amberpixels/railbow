# frozen_string_literal: true

require "date"
require "time"
require_relative "../clock"
require_relative "../git_utils"
require_relative "../multi_db"
require_relative "../params"

module Railbow
  module Status
    # Every git lookup db:migrate:status makes about one migrations directory:
    # authors, landing dates, originating branches and uncommitted files.
    class GitData
      EMPTY_AUTHORS = {names: {}, emails: {}}.freeze
      PORCELAIN_KINDS = {"??" => :untracked, "A " => :added, "AM" => :added, "M " => :edited}.freeze

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

      # One instance per migrations directory across a multi-database run, so
      # the full-history `git log` does not repeat once per database.
      def self.for(migrate_dir:, **opts)
        cache = Railbow::MultiDb.current&.git_cache
        return new(migrate_dir: migrate_dir, **opts) unless cache

        cache[[migrate_dir, opts]] ||= new(migrate_dir: migrate_dir, **opts)
      end

      # Basenames of the migrations the checked-out branch adds over its base:
      # committed since the merge-base, or added and not committed yet. Much
      # cheaper than a full instance (no history walk, no origin lookup), so a
      # database that is otherwise only summarized can afford to ask.
      def self.branch_files(paths, base_override: "")
        run_cached([:branch_files, paths, base_override]) do
          files = Set.new(committed_branch_paths(paths, base_override).map { |f| File.basename(f) })
          files.merge(uncommitted_branch_files(paths, base_override: base_override, additions_only: true))
        end
      end

      # Paths of the migrations committed on this branch since it left its
      # base. Shared with the origin badge, so the badge and the branch rows
      # agree on which migrations are the branch's.
      def self.committed_branch_paths(paths, base_override)
        merge_base = merge_base(base_override)
        return [] unless merge_base

        diff_out, diff_status = Railbow::GitUtils.capture2(
          "diff", "--name-status", "--diff-filter=AR", merge_base, "HEAD", "--", *paths
        )
        return [] unless diff_status.success?

        diff_out.each_line.filter_map { |l| name_status_path(l.strip) }
      end

      def self.merge_base(base_override)
        run_cached([:merge_base, base_override]) do
          out, status = Railbow::GitUtils.capture2("merge-base", "HEAD", default_branch(base_override))
          status.success? ? out.strip : nil
        end
      end

      # Memoized for the rest of a multi-database run, so per-database calls
      # share what does not depend on the database. Outside a run, no cache.
      def self.run_cached(key)
        cache = Railbow::MultiDb.current&.git_cache
        return yield unless cache
        return cache[key] if cache.key?(key)

        cache[key] = yield
      end

      def self.default_branch(override)
        return override if override && !override.empty?

        run_cached([:default_branch]) { detect_default_branch }
      end

      def self.detect_default_branch
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

      # --name-status lines are "A\tfilepath" or "Rnnn\told\tnew"; a rename
      # attributes to its destination.
      def self.name_status_path(line)
        cols = line.split("\t")
        filepath = cols[0]&.start_with?("R") ? cols[2] : cols[1]
        (filepath.nil? || filepath.empty?) ? nil : filepath
      end

      def self.name_status_basename(line)
        filepath = name_status_path(line)
        filepath && File.basename(filepath)
      end

      # Every migration with an uncommitted change, whoever it belongs to.
      # Files an in-progress merge brings in from MERGE_HEAD show up as staged
      # additions, so they are left out.
      def self.uncommitted_files(paths, entries: porcelain_entries(paths))
        Set.new(entries.map(&:last)) - incoming_merge_files(paths)
      end

      # The uncommitted migrations that are the branch's own work. A staged
      # addition or rename counts only when it is new over the merge-base:
      # renaming a base-branch migration back to its own name is staged against
      # HEAD, but adds nothing to the branch. A staged edit belongs to the
      # branch for the badge, but with additions_only it is not a migration the
      # branch adds.
      def self.uncommitted_branch_files(paths, base_override: "", additions_only: false, entries: porcelain_entries(paths))
        over_base = staged_over_base(paths, base_override) if entries.any? { |kind, _| kind == :added }

        mine = entries.filter_map do |kind, basename|
          keep =
            case kind
            when :untracked then true
            when :edited then !additions_only
            # Without a merge-base there is nothing to compare against.
            when :added then over_base.nil? || over_base.include?(basename)
            end
          basename if keep
        end

        Set.new(mine) - incoming_merge_files(paths)
      end

      # [kind, basename] per `git status --porcelain` line worth knowing about:
      # :untracked, :added (staged addition or rename) or :edited (staged edit).
      def self.porcelain_entries(paths)
        output, status = Railbow::GitUtils.capture2("status", "--porcelain", "--", *paths)
        return [] unless status.success?

        output.each_line.filter_map do |line|
          code = line[0..1]

          if code[0] == "R"
            # Rename: "R  old -> new". Take the destination.
            parts = line[3..].split(" -> ", 2)
            kind = :added
            filepath = (parts[1] || parts[0]).strip
          else
            kind = PORCELAIN_KINDS[code]
            next unless kind

            filepath = line[3..].strip
          end

          [kind, File.basename(filepath)] unless filepath.empty?
        end
      end

      # Basenames the index adds over the merge-base, or nil when there is no
      # merge-base to compare with.
      def self.staged_over_base(paths, base_override)
        merge_base = merge_base(base_override)
        return nil unless merge_base

        out, status = Railbow::GitUtils.capture2(
          "diff", "--cached", "--name-status", "--diff-filter=AR", merge_base, "--", *paths
        )
        return nil unless status.success?

        Set.new(out.each_line.filter_map { |l| name_status_basename(l.strip) })
      end

      def self.incoming_merge_files(paths)
        merging = run_cached([:merging]) { Railbow::GitUtils.capture3("rev-parse", "MERGE_HEAD")[2].success? }
        return Set.new unless merging

        output, _, status = Railbow::GitUtils.capture3(
          "diff", "--name-only", "--diff-filter=AR", "HEAD", "MERGE_HEAD", "--", *paths
        )
        return Set.new unless status.success?

        Set.new(output.each_line.map { |l| File.basename(l.strip) }.reject(&:empty?))
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
        entries = self.class.porcelain_entries([migrate_dir])
        @uncommitted_files = self.class.uncommitted_files([migrate_dir], entries: entries)

        # The branch's uncommitted files have no commit to attribute, so they
        # belong to whatever branch is checked out right now.
        mine = self.class.uncommitted_branch_files([migrate_dir], base_override: base_branch, entries: entries)
        return if mine.empty?

        current_branch = current_branch_name(branch_mask)
        mine.each { |f| @branch_origins[f] ||= current_branch }
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
              Railbow::Clock.in_zone(Time.iso8601(line.sub("COMMIT:", ""))).to_date
            rescue ArgumentError
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

      def name_status_basename(line)
        self.class.name_status_basename(line)
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
        self.class.default_branch(override)
      end

      def branch_migration_origins(base_branch, branch_mask)
        files = self.class.committed_branch_paths([migrate_dir], base_branch)
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

      # The commit that first produced this filename. A plain log shows no diff
      # for a merge commit, so a file named inside one (a migration
      # re-timestamped while merging the base branch in) needs the -m form,
      # oldest match first. -m stays a fallback: a later "merge main into
      # feature" commit lists every main migration as added against one parent,
      # and pick_origin_branch would then label those with the base branch.
      def adding_commit(filepath)
        commits = commits_touching(filepath, "-1")
        return nil if commits.nil?
        return commits.first if commits.any?

        commits_touching(filepath, "-m")&.last
      end

      def commits_touching(filepath, *flags)
        out, status = Railbow::GitUtils.capture2(
          "log", "--diff-filter=AR", "--format=%H", *flags, "--", filepath
        )
        return nil unless status.success?

        out.each_line.map(&:strip).reject(&:empty?)
      end

      def branches_containing(commit)
        branches_out, bs = Railbow::GitUtils.capture2(
          "branch", "--contains", commit, "--format=%(refname:short)"
        )
        return [] unless bs.success?

        branches_out.each_line.map(&:strip).reject(&:empty?)
      end

      # Picks the branch that introduced the commit: child branches drop out
      # (if A is an ancestor of B, the commit came from A), then the branch
      # with the most commits since wins, as the original rather than a fork.
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
        self.class.incoming_merge_files([migrate_dir])
      end
    end
  end
end
