# frozen_string_literal: true

require "date"
require_relative "../git_utils"
require_relative "../formatters/base"
require_relative "../migration_parser"
require_relative "../config"
require_relative "../table"
require_relative "../calendar"
require_relative "../logo"

# Override DatabaseTasks.migrate_status which is called by both
# db:migrate:status and db:migrate:status:<database_name> tasks.
module Railbow
  module MigrateStatusFormatter
    # Ghost migration data normalized for rendering, whether it came from
    # mighost's orphan classification or a live snapshot recovery.
    class GhostRow
      attr_reader :filename, :branch_name, :source, :superseded_by, :deleted_in_sha,
        :author_name, :author_email, :content

      def initialize(filename: nil, branch_name: nil, source: nil, superseded_by: nil,
        deleted_in_sha: nil, author_name: nil, author_email: nil, content: nil)
        @filename = filename
        @branch_name = branch_name
        @source = source
        @superseded_by = superseded_by
        @deleted_in_sha = deleted_in_sha
        @author_name = author_name
        @author_email = author_email
        @content = content
      end
    end

    private

    def mighost_attr(obj, name)
      obj.respond_to?(name) ? obj.public_send(name) : nil
    end

    def mighost_snapshot_content(version)
      Mighost::API.find_snapshot(version)&.content
    rescue
      nil
    end

    def load_ghost_rows(versions, with_content: false)
      # Detect once: OrphanedMigration carries the classification (supersession,
      # deletion commit) that a bare snapshot doesn't, and already honors
      # dismissals and hide_superseded.
      orphans = begin
        Mighost::API.orphaned_migrations.to_h { |o| [o.version.to_s, o] }
      rescue
        return {}
      end

      rows = {}
      versions.each do |v|
        # Absent from detect = deliberately suppressed (dismissed, or superseded
        # with hide_superseded on) - render as plain NO FILE, don't re-recover.
        next unless (orphan = orphans[v])

        if orphan.filename && !orphan.filename.empty?
          rows[v] = GhostRow.new(
            filename: orphan.filename,
            branch_name: orphan.branch_name,
            source: mighost_attr(orphan, :source),
            superseded_by: mighost_attr(orphan, :superseded_by),
            deleted_in_sha: mighost_attr(orphan, :deleted_in_sha),
            author_name: mighost_attr(orphan, :author_name),
            author_email: mighost_attr(orphan, :author_email),
            content: with_content ? mighost_snapshot_content(v) : nil
          )
        else
          # Detect reads stored snapshots only. A version it lists without a
          # filename has no snapshot yet, so fall back to live git/worktree
          # recovery - keeps fresh clones working with zero setup.
          snapshot = begin
            Mighost::API.find_or_recover_snapshot(v)
          rescue
            nil
          end
          next unless snapshot&.filename && !snapshot.filename.empty?

          rows[v] = GhostRow.new(
            filename: snapshot.filename,
            branch_name: snapshot.branch_name,
            source: mighost_attr(snapshot, :source),
            superseded_by: api_superseded_by(v),
            deleted_in_sha: mighost_attr(snapshot, :deleted_in_sha),
            author_name: mighost_attr(snapshot, :author_name),
            author_email: mighost_attr(snapshot, :author_email),
            content: with_content ? snapshot.content : nil
          )
        end
      end
      rows
    end

    def api_superseded_by(version)
      return nil unless Mighost::API.respond_to?(:superseded_by)

      Mighost::API.superseded_by(version)
    rescue
      nil
    end

    # One tag slot per ghost row; most informative wins.
    def ghost_tag(ghost)
      if ghost.superseded_by
        "\e[38;5;245m≡ #{ghost.superseded_by}\e[38;5;217m"
      elsif ghost.branch_name
        if ghost.source == "worktree"
          "\e[38;5;222m⌥ₜ#{ghost.branch_name}\e[38;5;217m"
        else
          "\e[38;5;222m⌥ #{ghost.branch_name}\e[38;5;217m"
        end
      elsif ghost.deleted_in_sha
        "\e[38;5;245m✂ deleted in:#{ghost.deleted_in_sha[0, 8]}\e[38;5;217m"
      end
    end

    def git_migration_authors(migrate_dir)
      output, _status = Railbow::GitUtils.capture2(
        "log", "--format=COMMIT:%aN\t%aE", "--diff-filter=AR", "--name-status", "--", migrate_dir
      )
      return {names: {}, emails: {}} if output.empty?

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
          # --name-status lines: "A\tfilepath" or "Rnnn\told\tnew"
          cols = line.split("\t")
          status_code = cols[0]
          filepath = if status_code&.start_with?("R")
            # Renamed: map the destination (new) filename to the author
            cols[2]
          else
            cols[1]
          end
          next unless filepath
          basename = File.basename(filepath)
          names[basename] ||= current_name
          emails[basename] ||= current_email
        end
      end
      {names: names, emails: emails}
    end

    # Returns a hash of basename → Date for when each migration file
    # first appeared on the mainline (merge commit date via --first-parent).
    def git_migration_landed_dates(migrate_dir)
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
          cols = line.split("\t")
          filepath = cols[0]&.start_with?("R") ? cols[2] : cols[1]
          next unless filepath
          basename = File.basename(filepath)
          dates[basename] ||= current_date
        end
      end
      dates
    end

    def current_git_email
      output, _status = Railbow::GitUtils.capture2("config", "user.email")
      output.strip.downcase
    end

    def current_git_name
      output, _status = Railbow::GitUtils.capture2("config", "user.name")
      output.strip
    end

    def apply_branch_mask(branch, branch_mask)
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

    def git_branch_migration_origins(migrate_dir, base_branch, branch_mask)
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

        # Find the commit that added or renamed this file
        commit_out, cs = Railbow::GitUtils.capture2(
          "log", "--diff-filter=AR", "--format=%H", "-1", "--", filepath
        )
        next unless cs.success?
        commit = commit_out.strip
        next if commit.empty?

        # Find branches containing this commit
        branches_out, bs = Railbow::GitUtils.capture2(
          "branch", "--contains", commit, "--format=%(refname:short)"
        )
        next unless bs.success?
        branches = branches_out.each_line.map(&:strip).reject(&:empty?)
        next if branches.empty?

        # Pick the branch that originally introduced the commit.
        # 1. Filter out child branches: if branch A is an ancestor of branch B,
        #    the commit was introduced in A, not B.
        # 2. Among remaining, prefer the branch with the MOST commits after the
        #    adding commit - it has been active longer since the commit was made,
        #    indicating it is the original branch (not a newer fork).
        best = if branches.size == 1
          branches.first
        else
          filtered = branches.reject do |b|
            branches.any? do |other|
              next false if other == b
              _, st = Railbow::GitUtils.capture2("merge-base", "--is-ancestor", other, b)
              st.success?
            end
          end
          filtered = branches if filtered.empty?

          if filtered.size == 1
            filtered.first
          else
            filtered.max_by do |b|
              count_out, _ = Railbow::GitUtils.capture2("rev-list", "--count", "#{commit}..#{b}")
              count_out.strip.to_i
            end
          end
        end

        # Apply mask
        label = best ? apply_branch_mask(best, branch_mask) : best

        origins[basename] = label
      end

      origins
    end

    def git_uncommitted_migration_files(migrate_dir)
      output, status = Railbow::GitUtils.capture2("status", "--porcelain", "--", migrate_dir)
      return Set.new unless status.success?

      result = Set.new
      output.each_line do |line|
        code = line[0..1]

        if code[0] == "R"
          # Rename: "R  old -> new" or "R100 old -> new"
          # Extract the destination (new) path
          parts = line[3..].split(" -> ", 2)
          filepath = (parts[1] || parts[0]).strip
        elsif ["??", "A ", "AM", "M "].include?(code)
          filepath = line[3..].strip
        else
          next
        end

        result << File.basename(filepath) unless filepath.empty?
      end

      # During an in-progress merge, files from MERGE_HEAD (e.g. main) appear
      # as staged additions. Exclude them so they aren't tagged as ours.
      result - git_incoming_merge_files(migrate_dir)
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

    def git_incoming_merge_files(migrate_dir)
      _, _, mh_status = Railbow::GitUtils.capture3("rev-parse", "MERGE_HEAD")
      return Set.new unless mh_status.success?

      output, _, status = Railbow::GitUtils.capture3(
        "diff", "--name-only", "--diff-filter=AR", "HEAD", "MERGE_HEAD", "--", migrate_dir
      )
      return Set.new unless status.success?

      Set.new(output.each_line.map { |l| File.basename(l.strip) }.reject(&:empty?))
    end

    def print_help
      Railbow.print_logo
      puts <<~HELP

        Enhanced db:migrate:status

        \e[1mUsage:\e[0m
          [RBW_*=value ...] rake db:migrate:status

        \e[1mOptions:\e[0m
          RBW_SINCE=<period>       Filter migrations by age (default: all)
                                   Values: all, 2mo, 1w, 30d, 1y, etc.
                                   Units: d (days), w (weeks), mo/m (months), y (years)

          RBW_DATE=<mode>          Date column format (default: full):
                                   full       - 2026-01-30 12:08:54 (column: Created At)
                                   rel        - ~3d ago
                                   short      - Jan 30 (column: Date)
                                   custom(…)  - user strftime, e.g. custom(%b %d, %Y)

          RBW_VIEW=<options>       Display options (comma-separated):
                                   calendar   - show month/year separator lines + week ticks
                                   tables     - parse migration files, show Tables column

          RBW_COMPACT=<options>    Compact display (comma-separated):
                                   oneline    - truncate instead of wrapping
                                   dense      - remove cell padding
                                   noheader   - hide table header row
                                   maxw:<n>   - cap column widths at n chars
                                   hide:<col> - hide a column by name (repeatable)

          RBW_CALENDAR=<options>   Calendar sub-options (requires RBW_VIEW=calendar):
                                   (empty)      - month separators only, no week
                                                  markers at all
                                   wticks       - week tick marks on the date column
                                   wdividers    - a separator row per ISO week
                                   counts       - append "· N migrations" to every
                                                  separator row (that section)
                                   label:<fmt>  - strftime for month separators
                                                  (default: %b %Y   W%V)
                                   wlabel:<fmt> - strftime for week separators
                                                  (default: same as label, so the
                                                  week number never shifts)

          RBW_GIT=<options>        Git integration (comma-separated):
                                   author     - add an Author column (same as author:all)
                                   author:all - add an Author column
                                   author:me  - highlight your own migrations
                                   diff       - tag migrations by git origin
                                   base:<branch> - base branch for diff (default: auto-detected)
                                   mask:<re>  - regex to extract branch label
                                                e.g. mask:(PS-[^/]+)/
                                   mask:auto  - auto-extract ticket id from branch name

          RBW_PLAIN=1              Disable Railbow formatting (plain Rails output)

          RBW_FORCE=1              Force Railbow formatting even when piped, in CI,
                                   or called by an LLM agent (RBW_PLAIN=1 still wins)

          RBW_HELP=1               Show this help message

        \e[2mAuto-disabled when piped, in CI, or when called by an LLM agent.\e[0m

        \e[1mExamples:\e[0m
          rake db:migrate:status
          RBW_SINCE=2mo RBW_VIEW=calendar rake db:migrate:status
          RBW_CALENDAR=wdividers,counts rake db:migrate:status
          RBW_VIEW=tables RBW_GIT=author rake db:migrate:status
          RBW_GIT=author:me RBW_SINCE=3mo rake db:migrate:status
          RBW_DATE=rel rake db:migrate:status
          RBW_DATE=short rake db:migrate:status
          RBW_DATE='custom(%b %d, %Y)' rake db:migrate:status
          RBW_GIT=diff rake db:migrate:status
          RBW_GIT=diff,base:develop rake db:migrate:status
          RBW_GIT=diff,mask:(PS-[^/]+)/ rake db:migrate:status

      HELP
    end

    public

    def migrate_status
      return super if Railbow.plain?

      if Railbow::Params.help?
        print_help
        return
      end

      unless migration_connection_pool.schema_migration.table_exists?
        Kernel.abort "Schema migrations table does not exist yet."
      end

      formatter = Railbow::Formatters::Base.new

      db_name = migration_connection_pool.db_config.database
      puts "\n#{formatter.emoji(:status)} Database: #{formatter.cyan(db_name)}"
      puts

      db_list = migration_connection_pool.migration_context.migrations_status

      if db_list.empty?
        puts formatter.yellow("  No migrations found")
        return
      end

      # Options from Railbow::Params
      since_value = Railbow::Params.since
      author_mode = Railbow::Params.git_author

      calendar_enabled = Railbow::Params.view_calendar?
      ticks_enabled = Railbow::Params.calendar_wticks?
      tables_enabled = Railbow::Params.view_tables?
      author_enabled = %w[all me].include?(author_mode)
      diff_enabled = Railbow::Params.git_diff?
      date_format = Railbow::Params.date_format
      nowrap_enabled = Railbow::Params.compact_oneline?
      base_override = Railbow::Params.git_base
      branch_mask = Railbow::Params.git_mask

      # Filter by SINCE period (default: all)
      since_cutoff = Railbow::Params.parse_since(since_value, context: "migrations")
      if since_cutoff
        total_count = db_list.size
        cutoff_version = since_cutoff.strftime("%Y%m%d%H%M%S").to_i
        db_list = db_list.select { |_, v, _| v.to_i >= cutoff_version }

        skipped = total_count - db_list.size
        if skipped > 0
          puts formatter.dim("  (#{skipped} older migrations hidden - SINCE=#{since_value})")
          puts
        end
      end

      if db_list.empty?
        puts formatter.yellow("  No migrations in the selected period")
        return
      end

      # Build version → filename lookup (needed for tables, author, or commit dates)
      version_to_file = {}
      migration_connection_pool.migration_context.migrations.each do |m|
        version_to_file[m.version.to_s] = m.filename
      end

      # Load git landed dates (always) and authors (if needed)
      author_names = {}
      author_emails = {}
      landed_dates = {}
      git_email = nil
      git_name = nil
      sample_file = version_to_file.values.first
      if sample_file
        migrate_dir = File.dirname(sample_file)
        landed_dates = git_migration_landed_dates(migrate_dir)
        if author_enabled
          result = git_migration_authors(migrate_dir)
          author_names = result[:names]
          author_emails = result[:emails]
        end
      end
      if author_enabled
        git_email = current_git_email
        git_name = current_git_name
      end

      # Load diff data if needed
      branch_origins = {}
      uncommitted_files = Set.new
      incoming_merge_files = Set.new
      merge_source_label = nil
      if diff_enabled && sample_file
        base_branch = detect_default_branch(base_override)
        branch_origins = git_branch_migration_origins(migrate_dir, base_branch, branch_mask)
        incoming_merge_files = git_incoming_merge_files(migrate_dir)
        if incoming_merge_files.any?
          merge_source_label = detect_merge_source_label(branch_mask)
        end
        uncommitted_files = git_uncommitted_migration_files(migrate_dir)
        # Assign current branch as origin for uncommitted files
        current_branch = current_branch_name(branch_mask)
        uncommitted_files.each { |f| branch_origins[f] ||= current_branch }
      end

      # Load mighost ghost data for "NO FILE" migrations (if mighost gem is available)
      mighost_snapshots = {}
      mighost_available = defined?(Mighost::API) && Mighost.enabled?
      if mighost_available
        no_file_versions = db_list.select { |_, _, n| n.include?("NO FILE") }.map { |_, v, _| v.to_s }
        mighost_snapshots = load_ghost_rows(no_file_versions, with_content: tables_enabled) if no_file_versions.any?
      end

      # Build columns
      # Latest migration ID date - used to determine "fresh" landed badges
      latest_version = db_list.last&.dig(1).to_s
      latest_mig_date = begin
        Date.new(latest_version[0..3].to_i, latest_version[4..5].to_i, latest_version[6..7].to_i)
      rescue Date::Error
        nil
      end

      has_landed_tags = landed_dates.any? do |basename, cdate|
        v = basename[0..13]
        mig_date = begin
          Date.new(v[0..3].to_i, v[4..5].to_i, v[6..7].to_i)
        rescue Date::Error
          nil
        end
        mig_date && (cdate - mig_date) > 7
      end
      needs_name_truncation = tables_enabled || author_mode == "all" || diff_enabled || has_landed_tags
      name_col_width = needs_name_truncation ? 60 : nil
      table_columns = [
        Railbow::Table::Column.new(label: "Status", max_width: 6, sticky: true, accent: true),
        Railbow::Table::Column.new(label: "Migration ID", sticky: true),
        Railbow::Table::Column.new(label: (date_format == "full") ? "Created At" : "Date"),
        Railbow::Table::Column.new(label: "Migration Name",
          max_width: name_col_width,
          truncate: needs_name_truncation)
      ]
      table_columns << Railbow::Table::Column.new(label: "Who") if author_mode == "all"
      if tables_enabled
        tables_truncate_fn = ->(cell_raw, max_w) { formatter.table_tags_fitted(cell_raw, max_w) }
        table_columns << Railbow::Table::Column.new(label: "Tables", truncate: nowrap_enabled, truncate_fn: tables_truncate_fn)
      end

      # Pre-resolve author name collisions for the "Who" column
      author_display = if author_mode == "all"
        all_raw_authors = author_names.values.compact
        all_raw_authors << git_name if git_name
        mighost_snapshots.each_value do |snap|
          all_raw_authors << snap.author_name if snap.respond_to?(:author_name) && snap.author_name
        end
        Railbow::Params.format_authors(all_raw_authors)
      else
        {}
      end

      # Build rows and track highlight/ghost/down indices
      highlight_rows = Set.new
      ghost_rows = Set.new
      down_rows = Set.new
      rows = db_list.each_with_index.map do |(status, version, name), idx|
        # A pending migration is not in effect yet: grey the whole row out so it
        # reads as inactive next to the applied ones.
        down_rows << idx if status == "down"
        colored_status = case status
        when "up" then formatter.green_bold("up")
        when "down" then formatter.yellow_bold("down")
        else status
        end
        ghost_snapshot = name.include?("NO FILE") ? mighost_snapshots[version.to_s] : nil
        if name.include?("NO FILE") && ghost_snapshot
          ghost_rows << idx
          # Mighost recovered this ghost migration - show ghost status + name + badge.
          # A superseded ghost lives on under another version: stale bookkeeping,
          # not a lost migration, so it gets a calmer glyph.
          colored_status = ghost_snapshot.superseded_by ? "🪦" : "👻"
          ghost_name = ghost_snapshot.filename
            .sub(/\A\d+_/, "")    # strip version prefix
            .sub(/\.rb\z/, "")    # strip extension
            .tr("_", " ")
            .gsub(/\b\w/, &:upcase) # titleize
          ghost_badge = ghost_tag(ghost_snapshot)
          if ghost_badge && name_col_width
            tag_width = formatter.display_width(formatter.strip_ansi(ghost_badge))
            available = name_col_width - tag_width - 2
            ghost_name = formatter.truncate_str(ghost_name, available)
            name_width = formatter.display_width(ghost_name)
            padding = name_col_width - name_width - tag_width
            display_name = "#{ghost_name}#{" " * [padding, 2].max}#{ghost_badge}"
          elsif ghost_badge
            display_name = "#{ghost_name}  #{ghost_badge}"
          else
            display_name = ghost_name
          end
        elsif name.include?("NO FILE")
          display_name = formatter.red("NO FILE")
        else
          display_name = name
        end

        if !name.include?("NO FILE")
          filepath = version_to_file[version.to_s]
          basename = filepath ? File.basename(filepath) : nil

          # Diff tag (branch origin badge)
          diff_tag = nil
          if diff_enabled && basename
            if incoming_merge_files.include?(basename)
              colored_status = "#{colored_status} \e[38;5;213m\u2B07#{Railbow::Formatters::Base::RESET}"
              diff_tag = formatter.diff_tag_merging(merge_source_label || "merge")
            elsif uncommitted_files.include?(basename)
              highlight_rows << idx
              colored_status = "#{colored_status} \e[38;5;220m\u25c6#{Railbow::Formatters::Base::RESET}"
            end

            diff_tag ||= if branch_origins.key?(basename)
              formatter.diff_tag_branch(branch_origins[basename])
            end
          end

          # Landed badge: show ↪ date when commit date is >7 days after migration ID date
          landed_tag = nil
          if basename && landed_dates[basename]
            v = version.to_s
            mig_date = begin
              Date.new(v[0..3].to_i, v[4..5].to_i, v[6..7].to_i)
            rescue Date::Error
              nil
            end
            if mig_date && (landed_dates[basename] - mig_date) > 7
              fresh = latest_mig_date && landed_dates[basename] >= latest_mig_date
              landed_tag = formatter.landed_tag(landed_dates[basename], fresh: fresh)
            end
          end

          # Append tags to display_name with right-alignment
          tags = [landed_tag, diff_tag].compact.join(" ")
          if !tags.empty? && name_col_width
            tags_width = formatter.display_width(formatter.strip_ansi(tags))
            available = name_col_width - tags_width - 2
            display_name = formatter.truncate_str(display_name, available)
            name_width = formatter.display_width(formatter.strip_ansi(display_name))
            padding = name_col_width - name_width - tags_width
            display_name = "#{display_name}#{" " * [padding, 2].max}#{tags}"
          elsif !tags.empty?
            display_name = "#{display_name}  #{tags}"
          end
        end

        created_at = formatter.format_date(version, date_format)
        row = [colored_status, version.to_s, created_at, display_name]

        if author_enabled
          if ghost_snapshot
            # Use mighost snapshot author data for ghost migrations
            if author_mode == "all"
              ghost_author = ghost_snapshot.respond_to?(:author_name) ? ghost_snapshot.author_name : nil
              raw = ghost_author || ""
              row << (author_display[raw] || Railbow::Params.format_author(raw))
              if git_email && ghost_snapshot.respond_to?(:author_email)
                ghost_email = ghost_snapshot.author_email&.downcase
                highlight_rows << idx if ghost_email && ghost_email == git_email
              end
            elsif author_mode == "me" && git_email && ghost_snapshot.respond_to?(:author_email)
              ghost_email = ghost_snapshot.author_email&.downcase
              highlight_rows << idx if ghost_email && ghost_email == git_email
            end
          else
            filepath = version_to_file[version.to_s]
            basename = filepath ? File.basename(filepath) : nil

            # Uncommitted migrations have no git author - treat them as mine.
            # Match by email first; fall back to author name to handle cases where
            # the commit email differs from git config (e.g. GitHub noreply emails
            # after squash-merge, or mailmap rewrites).
            if author_mode == "all"
              author = basename ? author_names[basename] : nil
              raw = author || (basename ? git_name : "")
              row << (author_display[raw] || Railbow::Params.format_author(raw))
              if git_email
                email = author_emails[basename]
                name = author_names[basename]
                highlight_rows << idx if email.nil? || email == git_email ||
                  (git_name && name && name.downcase == git_name.downcase)
              end
            elsif author_mode == "me" && basename && git_email
              email = author_emails[basename]
              name = author_names[basename]
              highlight_rows << idx if email.nil? || email == git_email ||
                (git_name && name && name.downcase == git_name.downcase)
            end
          end
        end

        if tables_enabled
          tables = if ghost_snapshot&.content && !ghost_snapshot.content.empty?
            Railbow::MigrationParser.extract_tables_from_content(ghost_snapshot.content)
          else
            Railbow::MigrationParser.extract_tables(version_to_file[version.to_s])
          end
          row << formatter.table_tags(tables)
        end

        row
      end

      # Calendar furniture: month separators, week separators, week ticks
      calendar = if calendar_enabled
        Railbow::Calendar.build(
          db_list.map { |_, v, _| v.to_s },
          weeks: Railbow::Params.calendar_wdividers?,
          ticks: ticks_enabled,
          counts: Railbow::Params.calendar_counts?,
          month_label: Railbow::Params.calendar_label,
          week_label: Railbow::Params.calendar_week_label
        )
      else
        Railbow::Calendar.none
      end

      renderer = Railbow::Table::Renderer.new(
        columns: table_columns,
        theme: Railbow::Table::Themes::WALLS,
        compact: Railbow::Params.compact_options,
        aliases: Railbow::Config.table_aliases
      )
      tick_col = 2 # Date column index
      puts renderer.render(rows,
        separators: calendar.separators,
        highlight_rows: highlight_rows, ghost_rows: ghost_rows, dim_rows: down_rows,
        tick_rows: calendar.tick_rows, tick_col: tick_col)
    end
  end
end

ActiveRecord::Tasks::DatabaseTasks.prepend(Railbow::MigrateStatusFormatter)
