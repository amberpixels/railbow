# frozen_string_literal: true

require "date"
require "open3"
require_relative "../formatters/base"
require_relative "../migration_parser"
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

    def parse_since(value)
      return nil if value.nil? || value.strip.downcase == "all"

      match = value.strip.match(/^(\d+)(d|w|mo|m|y)$/i)
      unless match
        warn "  Warning: unrecognized SINCE=#{value}, showing all migrations"
        return nil
      end

      amount = match[1].to_i
      unit = match[2].downcase

      case unit
      when "d" then Date.today - amount
      when "w" then Date.today - (amount * 7)
      when "mo", "m" then Date.today.prev_month(amount)
      when "y" then Date.today.prev_year(amount)
      end
    end

    def print_help
      Railbow.print_logo
      puts <<~HELP

        Enhanced db:migrate:status

        \e[1mUsage:\e[0m
          rake db:migrate:status [ENV_VAR=value ...]

        \e[1mOptions:\e[0m
          SINCE=<period>     Filter migrations by age (default: all)
                             Values: all, 2mo, 1w, 30d, 1y, etc.
                             Units: d (days), w (weeks), mo/m (months), y (years)

          CALENDAR=1         Show month/year separator lines between groups

          TABLES=1           Parse migration files and show a Tables column
                             with colored tags for each referenced table

          AUTHOR=<mode>      Show migration file authors from git history
                             off  — disabled (default)
                             all  — add an Author column
                             me   — highlight your own migrations (via git config user.name)

          HELP=1             Show this help message

        \e[1mExamples:\e[0m
          rake db:migrate:status
          SINCE=2mo CALENDAR=1 rake db:migrate:status
          TABLES=1 AUTHOR=all rake db:migrate:status
          AUTHOR=me SINCE=3mo rake db:migrate:status

      HELP
    end

    public

    def migrate_status
      if ENV["HELP"] == "1"
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

      # Options from ENV
      since_value = ENV.fetch("SINCE", "all")
      show_calendar = ENV.fetch("CALENDAR", "0")
      show_tables = ENV.fetch("TABLES", "0")
      author_mode = ENV.fetch("AUTHOR", "off").strip.downcase

      calendar_enabled = %w[1 true yes on].include?(show_calendar.strip.downcase)
      tables_enabled = %w[1 true yes on].include?(show_tables.strip.downcase)
      author_enabled = %w[all me].include?(author_mode)

      # Filter by SINCE period (default: all)
      since_cutoff = parse_since(since_value)
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
      if tables_enabled || author_enabled
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

      # Build header
      name_col_width = 50
      header = ["Status", "Migration ID", "Created At", "Migration Name"]
      header << "Author" if author_mode == "all"
      header << "Tables" if tables_enabled

      # Build rows and track highlight indices for AUTHOR=me
      highlight_rows = Set.new
      rows = db_list.each_with_index.map do |(status, version, name), idx|
        colored_status = case status
        when "up" then formatter.green_bold("up")
        when "down" then formatter.yellow_bold("down")
        else status
        end
        display_name = name.include?("NO FILE") ? formatter.red("NO FILE") : name
        row = [colored_status, version.to_s, formatter.format_timestamp(version), display_name]

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

      # Truncation for name column
      truncate = {}
      truncate[3] = name_col_width if tables_enabled || author_mode == "all"

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

      puts formatter.render_table(header, rows,
        separators: separators, truncate_cols: truncate, highlight_rows: highlight_rows)
    end
  end
end

ActiveRecord::Tasks::DatabaseTasks.prepend(Railbow::MigrateStatusFormatter)
