# frozen_string_literal: true

require "date"
require_relative "../formatters/base"
require_relative "../table"
require_relative "../config"
require_relative "fixtures"

module Railbow
  module Demo
    class StatusDemo
      def self.run
        new.run
      end

      def run
        formatter = Railbow::Formatters::Base.new
        migrations = Fixtures.migrations

        puts "\n#{formatter.emoji(:status)} Database: #{formatter.cyan("db/development.sqlite3")}"
        puts

        # Use default config: author:me, diff, calendar, tables, wticks, full date
        date_format = "full"
        tables_enabled = true
        diff_enabled = true

        git_email = Fixtures::DEMO_USER_EMAIL
        git_name = Fixtures::DEMO_USER_NAME

        # Latest migration date — for "fresh" landed badge detection
        latest_version = migrations.last[:version]
        latest_mig_date = parse_version_date(latest_version)

        # Check if any landed tags exist
        has_landed_tags = migrations.any? { |m|
          next false unless m[:landed_date]
          mig_date = parse_version_date(m[:version])
          mig_date && (m[:landed_date] - mig_date) > 7
        }

        needs_name_truncation = tables_enabled || diff_enabled || has_landed_tags
        name_col_width = needs_name_truncation ? 60 : nil

        table_columns = [
          Railbow::Table::Column.new(label: "Status", max_width: 6, sticky: true, accent: true),
          Railbow::Table::Column.new(label: "Migration ID", sticky: true),
          Railbow::Table::Column.new(label: "Created At"),
          Railbow::Table::Column.new(label: "Migration Name",
            max_width: name_col_width,
            truncate: needs_name_truncation)
        ]
        # No Author column in default config (author:me only highlights)

        tables_truncate_fn = ->(cell_raw, max_w) { formatter.table_tags_fitted(cell_raw, max_w) }
        table_columns << Railbow::Table::Column.new(label: "Tables", truncate: true, truncate_fn: tables_truncate_fn)

        # Build rows
        highlight_rows = Set.new
        down_rows = Set.new
        rows = migrations.each_with_index.map do |m, idx|
          down_rows << idx if m[:status] == "down"
          colored_status = case m[:status]
          when "up" then formatter.green_bold("up")
          when "down" then formatter.yellow_bold("down")
          else m[:status]
          end

          display_name = m[:name]

          # Diff tag (branch badge)
          diff_tag = m[:branch] ? formatter.diff_tag_branch(m[:branch]) : nil

          # Landed badge
          landed_tag = nil
          if m[:landed_date]
            mig_date = parse_version_date(m[:version])
            if mig_date && (m[:landed_date] - mig_date) > 7
              fresh = latest_mig_date && m[:landed_date] >= latest_mig_date
              landed_tag = formatter.landed_tag(m[:landed_date], fresh: fresh)
            end
          end

          # Append tags to display_name
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

          created_at = formatter.format_date(m[:version], date_format)

          # Highlight current user's rows (author:me mode)
          if m[:author_email] == git_email ||
              (git_name && m[:author_name] && m[:author_name].downcase == git_name.downcase)
            highlight_rows << idx
          end

          # Table tags
          table_tags = formatter.table_tags(m[:tables])

          [colored_status, m[:version], created_at, display_name, table_tags]
        end

        # Calendar separators
        separators = {}
        versions = migrations.map { |m| m[:version] }
        month_keys = versions.map { |v| v[0..5] }
        calendar_label_fmt = "%b %Y   W%V"

        if month_keys.uniq.size > 1
          month_keys.each_with_index do |mk, i|
            next if i == 0
            if mk != month_keys[i - 1]
              v = versions[i]
              date = Date.new(v[0..3].to_i, v[4..5].to_i, v[6..7].to_i)
              separators[i] = date.strftime(calendar_label_fmt)
            end
          end
        end

        # Week ticks
        tick_rows = Set.new
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

        aliases = Railbow::Config.table_aliases
        renderer = Railbow::Table::Renderer.new(
          columns: table_columns,
          theme: Railbow::Table::Themes::WALLS,
          compact: {oneline: false, dense: false, noheader: false, maxw: nil, hidden_columns: []},
          aliases: aliases
        )
        puts renderer.render(rows, separators: separators, highlight_rows: highlight_rows,
          dim_rows: down_rows, tick_rows: tick_rows, tick_col: 2)
      end

      private

      def parse_version_date(version)
        v = version.to_s
        Date.new(v[0..3].to_i, v[4..5].to_i, v[6..7].to_i)
      rescue Date::Error
        nil
      end
    end
  end
end
