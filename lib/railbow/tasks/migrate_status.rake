# frozen_string_literal: true

require "date"
require "open3"
require_relative "../formatters/base"
require_relative "../migration_parser"
require_relative "../table"
require_relative "../logo"

# Override DatabaseTasks.migrate_status which is called by both
# db:migrate:status and db:migrate:status:<database_name> tasks.
module Railbow
  module MigrateStatusFormatter
    private

    def git_migration_authors(migrate_dir)
      output, _status = Open3.capture2(
        "git", "log", "--format=COMMIT:%aN\t%aE", "--diff-filter=A", "--name-only", "--", migrate_dir
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
          basename = File.basename(line)
          names[basename] ||= current_name
          emails[basename] ||= current_email
        end
      end
      {names: names, emails: emails}
    end

    def current_git_email
      output, _status = Open3.capture2("git", "config", "user.email")
      output.strip.downcase
    end

    def current_git_name
      output, _status = Open3.capture2("git", "config", "user.name")
      output.strip
    end

    def current_branch_name(branch_mask)
      output, status = Open3.capture2("git", "rev-parse", "--abbrev-ref", "HEAD")
      return "HEAD" unless status.success?

      branch = output.strip
      if !branch_mask.empty?
        m = branch.match(Regexp.new(branch_mask, Regexp::IGNORECASE))
        branch = m[1] if m && m[1]
      end
      branch
    end

    def detect_default_branch(override)
      return override if override && !override.empty?

      output, status = Open3.capture2("git", "symbolic-ref", "refs/remotes/origin/HEAD")
      if status.success?
        branch = output.strip.sub(%r{^refs/remotes/origin/}, "")
        return branch unless branch.empty?
      end

      %w[main master].each do |candidate|
        _, st = Open3.capture2("git", "rev-parse", "--verify", "refs/heads/#{candidate}")
        return candidate if st.success?
      end

      "main"
    end

    def git_branch_migration_origins(migrate_dir, base_branch, branch_mask)
      merge_base_out, mb_status = Open3.capture2("git", "merge-base", "HEAD", base_branch)
      return {} unless mb_status.success?

      merge_base = merge_base_out.strip
      diff_out, diff_status = Open3.capture2(
        "git", "diff", "--name-only", "--diff-filter=A", merge_base, "HEAD", "--", migrate_dir
      )
      return {} unless diff_status.success?

      files = diff_out.each_line.map(&:strip).reject(&:empty?)
      origins = {}

      files.each do |filepath|
        basename = File.basename(filepath)

        # Find the commit that added this file
        commit_out, cs = Open3.capture2(
          "git", "log", "--diff-filter=A", "--format=%H", "-1", "--", filepath
        )
        next unless cs.success?
        commit = commit_out.strip
        next if commit.empty?

        # Find branches containing this commit
        branches_out, bs = Open3.capture2(
          "git", "branch", "--contains", commit, "--format=%(refname:short)"
        )
        next unless bs.success?
        branches = branches_out.each_line.map(&:strip).reject(&:empty?)
        next if branches.empty?

        # Pick the branch that originally introduced the commit.
        # 1. Filter out child branches: if branch A is an ancestor of branch B,
        #    the commit was introduced in A, not B.
        # 2. Among remaining, prefer the branch with the MOST commits after the
        #    adding commit — it has been active longer since the commit was made,
        #    indicating it is the original branch (not a newer fork).
        best = if branches.size == 1
          branches.first
        else
          filtered = branches.reject do |b|
            branches.any? do |other|
              next false if other == b
              _, st = Open3.capture2("git", "merge-base", "--is-ancestor", other, b)
              st.success?
            end
          end
          filtered = branches if filtered.empty?

          if filtered.size == 1
            filtered.first
          else
            filtered.max_by do |b|
              count_out, _ = Open3.capture2("git", "rev-list", "--count", "#{commit}..#{b}")
              count_out.strip.to_i
            end
          end
        end

        # Apply mask
        label = best
        if !branch_mask.empty? && best
          m = best.match(Regexp.new(branch_mask, Regexp::IGNORECASE))
          label = m[1] if m && m[1]
        end

        origins[basename] = label
      end

      origins
    end

    def git_uncommitted_migration_files(migrate_dir)
      output, status = Open3.capture2("git", "status", "--porcelain", "--", migrate_dir)
      return Set.new unless status.success?

      result = Set.new
      output.each_line do |line|
        code = line[0..1]
        next unless ["??", "A ", "AM", "M "].include?(code)

        filepath = line[3..].strip
        result << File.basename(filepath) unless filepath.empty?
      end
      result
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
                                   full       — 2026-01-30 12:08:54 (column: Created At)
                                   rel        — ~3d ago
                                   short      — Jan 30 (column: Date)
                                   custom(…)  — user strftime, e.g. custom(%b %d, %Y)

          RBW_VIEW=<options>       Display options (comma-separated):
                                   calendar   — show month/year separator lines + week ticks
                                   tables     — parse migration files, show Tables column
                                   tables:nowrap — truncate Tables column instead of wrapping

          RBW_CALENDAR=<options>  Calendar sub-options (requires RBW_VIEW=calendar):
                                   wticks     — show week tick marks on date column

          RBW_GIT=<options>        Git integration (comma-separated):
                                   author     — add an Author column (same as author:all)
                                   author:all — add an Author column
                                   author:me  — highlight your own migrations
                                   diff       — tag migrations by git origin
                                   base:<branch> — base branch for diff (default: auto-detected)
                                   mask:<re>  — regex to extract branch label
                                                e.g. mask:(WS-[^/]+)/

          RBW_PLAIN=1              Disable Railbow formatting (plain Rails output)

          RBW_HELP=1               Show this help message

        \e[2mAuto-disabled when piped, in CI, or when called by an LLM agent.\e[0m

        \e[1mExamples:\e[0m
          rake db:migrate:status
          RBW_SINCE=2mo RBW_VIEW=calendar rake db:migrate:status
          RBW_VIEW=tables RBW_GIT=author rake db:migrate:status
          RBW_GIT=author:me RBW_SINCE=3mo rake db:migrate:status
          RBW_DATE=rel rake db:migrate:status
          RBW_DATE=short rake db:migrate:status
          RBW_DATE=custom(%b\ %d,\ %Y) rake db:migrate:status
          RBW_GIT=diff rake db:migrate:status
          RBW_GIT=diff,base:develop rake db:migrate:status
          RBW_GIT=diff,mask:(WS-[^/]+)/ rake db:migrate:status

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
      nowrap_enabled = Railbow::Params.view_tables_nowrap?
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
          puts formatter.dim("  (#{skipped} older migrations hidden — SINCE=#{since_value})")
          puts
        end
      end

      if db_list.empty?
        puts formatter.yellow("  No migrations in the selected period")
        return
      end

      # Build version → filename lookup (needed for tables or author)
      version_to_file = {}
      if tables_enabled || author_enabled || diff_enabled
        migration_connection_pool.migration_context.migrations.each do |m|
          version_to_file[m.version.to_s] = m.filename
        end
      end

      # Load git authors if needed
      author_names = {}
      author_emails = {}
      git_email = nil
      git_name = nil
      if author_enabled
        sample_file = version_to_file.values.first
        if sample_file
          migrate_dir = File.dirname(sample_file)
          result = git_migration_authors(migrate_dir)
          author_names = result[:names]
          author_emails = result[:emails]
        end
        git_email = current_git_email if author_mode == "me"
        git_name = current_git_name if author_mode == "all"
      end

      # Load diff data if needed
      branch_origins = {}
      uncommitted_files = Set.new
      if diff_enabled
        sample_file = version_to_file.values.first
        if sample_file
          migrate_dir = File.dirname(sample_file)
          base_branch = detect_default_branch(base_override)
          branch_origins = git_branch_migration_origins(migrate_dir, base_branch, branch_mask)
          uncommitted_files = git_uncommitted_migration_files(migrate_dir)
          # Assign current branch as origin for uncommitted files
          current_branch = current_branch_name(branch_mask)
          uncommitted_files.each { |f| branch_origins[f] ||= current_branch }
        end
      end

      # Build columns
      needs_name_truncation = tables_enabled || author_mode == "all" || diff_enabled
      name_col_width = needs_name_truncation ? 60 : nil
      table_columns = [
        Railbow::Table::Column.new(label: "Live", max_width: 5),
        Railbow::Table::Column.new(label: "Migration ID"),
        Railbow::Table::Column.new(label: date_format == "full" ? "Created At" : "Date"),
        Railbow::Table::Column.new(label: "Migration Name",
          max_width: name_col_width,
          truncate: needs_name_truncation)
      ]
      table_columns << Railbow::Table::Column.new(label: "Author") if author_mode == "all"
      if tables_enabled
        tables_truncate_fn = ->(cell_raw, max_w) { formatter.table_tags_fitted(cell_raw, max_w) }
        table_columns << Railbow::Table::Column.new(label: "Tables", truncate: nowrap_enabled, truncate_fn: tables_truncate_fn)
      end

      # Build rows and track highlight indices for AUTHOR=me
      highlight_rows = Set.new
      rows = db_list.each_with_index.map do |(status, version, name), idx|
        colored_status = case status
        when "up" then formatter.green_bold("\u2191\u2191")
        when "down" then formatter.yellow_bold("\u2193\u2193")
        else status
        end
        display_name = name.include?("NO FILE") ? formatter.red("NO FILE") : name

        if diff_enabled && !name.include?("NO FILE")
          filepath = version_to_file[version.to_s]
          basename = filepath ? File.basename(filepath) : nil

          if basename && uncommitted_files.include?(basename)
            highlight_rows << idx
            colored_status = "#{colored_status} \e[38;5;220m\u25c6#{Railbow::Formatters::Base::RESET}"
          end

          diff_tag = if basename && branch_origins.key?(basename)
            formatter.diff_tag_branch(branch_origins[basename])
          end

          if diff_tag && name_col_width
            tag_width = formatter.display_width(formatter.strip_ansi(diff_tag))
            available = name_col_width - tag_width - 2
            display_name = formatter.truncate_str(display_name, available)
            name_width = formatter.display_width(formatter.strip_ansi(display_name))
            padding = name_col_width - name_width - tag_width
            display_name = "#{display_name}#{" " * [padding, 2].max}#{diff_tag}"
          end
        end

        created_at = formatter.format_date(version, date_format)
        row = [colored_status, version.to_s, created_at, display_name]

        if author_enabled
          filepath = version_to_file[version.to_s]
          basename = filepath ? File.basename(filepath) : nil

          # Uncommitted migrations have no git author — treat them as mine
          if author_mode == "all"
            author = basename ? author_names[basename] : nil
            row << (author || (basename ? git_name : ""))
          elsif author_mode == "me" && basename && git_email
            email = author_emails[basename]
            highlight_rows << idx if email.nil? || email == git_email
          end
        end

        if tables_enabled
          tables = Railbow::MigrationParser.extract_tables(version_to_file[version.to_s])
          row << formatter.table_tags(tables)
        end

        row
      end

      # Calendar separators
      separators = {}
      if calendar_enabled
        versions = db_list.map { |_, v, _| v.to_s }
        month_keys = versions.map { |v| v[0..5] }

        if month_keys.uniq.size > 1
          month_keys.each_with_index do |mk, i|
            next if i == 0
            if mk != month_keys[i - 1]
              year = mk[0..3]
              month_name = Date::ABBR_MONTHNAMES[mk[4..5].to_i]
              separators[i] = "#{month_name} #{year}"
            end
          end
        end
      end

      # Week tick separators: mark first row of each new ISO week
      tick_rows = Set.new
      if ticks_enabled
        versions = db_list.map { |_, v, _| v.to_s }
        prev_week = nil
        versions.each_with_index do |v, i|
          y = v[0..3].to_i
          m = v[4..5].to_i
          d = v[6..7].to_i
          next if y == 0 || m == 0 || d == 0

          week = Date.new(y, m, d).cweek

          if i > 0 && prev_week && week != prev_week
            tick_rows << i
          end

          prev_week = week
        end
      end

      renderer = Railbow::Table::Renderer.new(
        columns: table_columns,
        theme: Railbow::Table::Themes::WALLS
      )
      tick_col = 2 # Date column index
      puts renderer.render(rows, separators: separators, highlight_rows: highlight_rows, tick_rows: tick_rows, tick_col: tick_col)
    end
  end
end

ActiveRecord::Tasks::DatabaseTasks.prepend(Railbow::MigrateStatusFormatter)
