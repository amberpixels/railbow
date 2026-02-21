# frozen_string_literal: true

require "io/console"
require "unicode/display_width"

module Shine
  module Formatters
    class Base
      RESET = "\e[0m"
      BOLD  = "\e[1m"
      GREEN = "\e[32m"
      YELLOW = "\e[33m"
      RED   = "\e[31m"
      CYAN  = "\e[36m"
      BG_PURPLE = "\e[48;5;99m"
      WHITE = "\e[97m"

      def green(str)  = "#{GREEN}#{str}#{RESET}"
      def yellow(str) = "#{YELLOW}#{str}#{RESET}"
      def red(str)    = "#{RED}#{str}#{RESET}"
      def cyan(str)   = "#{CYAN}#{str}#{RESET}"
      def bold(str)   = "#{BOLD}#{str}#{RESET}"
      def green_bold(str) = "#{GREEN}#{BOLD}#{str}#{RESET}"
      def yellow_bold(str) = "#{YELLOW}#{BOLD}#{str}#{RESET}"

      def format_timing(seconds)
        milliseconds = (seconds * 1000).round(1)

        timing_str = if milliseconds < 1
          "#{(milliseconds * 1000).round(0)}μs"
        else
          "#{milliseconds}ms"
        end

        cyan(timing_str)
      end

      def emoji(type)
        case type
        when :migrating then "🚀"
        when :migrated  then "✅"
        when :reverting then "⏪"
        when :reverted  then "✅"
        when :check     then "✓"
        when :status    then "📊"
        else ""
        end
      end

      def format_timestamp(timestamp)
        ts = timestamp.to_s
        return ts if ts.length != 14

        "#{ts[0..3]}-#{ts[4..5]}-#{ts[6..7]} #{ts[8..9]}:#{ts[10..11]}:#{ts[12..13]}"
      end

      def render_table(header, rows)
        all_rows = [header] + rows
        last = header.size - 1

        # For non-last columns, measure max width across all rows.
        # For the last column, don't pad — it will be wrapped to terminal width.
        col_widths = header.each_index.map do |i|
          next 0 if i == last
          all_rows.map { |row| display_width(strip_ansi(row[i].to_s)) }.max
        end

        # Prefix = all columns except last, with their padding and separators.
        # Each cell is " content<padding> " and cells are joined by "│" (1 char).
        # So prefix width = sum of (col_width + 2) for each non-last col + (num_separators).
        prefix_width = col_widths[0...last].sum { |w| w + 2 } + last + 1

        term_width = terminal_width
        last_col_max = term_width ? [term_width - prefix_width, 10].max : nil

        fmt_row = ->(row) {
          prefix = row[0...last].each_with_index.map { |cell, i|
            s = cell.to_s
            padding = " " * (col_widths[i] - display_width(strip_ansi(s)))
            " #{s}#{padding} "
          }.join("│")

          last_cell = strip_ansi(row[last].to_s)
          prefix << "│"

          if last_col_max && display_width(last_cell) > last_col_max
            blank_prefix = row[0...last].each_with_index.map { |_, i|
              " " * (col_widths[i] + 2)
            }.join("│")
            blank_prefix << "│"

            wrapped = word_wrap(last_cell, last_col_max)
            prefix + " #{wrapped.first} \n" +
              wrapped[1..].map { |line| "#{blank_prefix} #{line} " }.join("\n")
          else
            prefix + " #{row[last]} "
          end
        }

        fmt_header = ->(row) {
          row.each_with_index.map { |cell, i|
            s = cell.to_s
            padding = i == last ? "" : " " * (col_widths[i] - display_width(strip_ansi(s)))
            " #{BG_PURPLE}#{BOLD}#{WHITE}#{s}#{padding}#{RESET} "
          }.join(" ")
        }

        lines = []
        lines << fmt_header.call(header)
        rows.each { |row| lines << fmt_row.call(row) }
        lines.join("\n")
      end

      private

      def terminal_width
        return $stdout.winsize[1] if $stdout.respond_to?(:winsize) && $stdout.tty?
        nil
      rescue StandardError
        nil
      end

      def word_wrap(str, max_width)
        return [str] if display_width(str) <= max_width

        lines = []
        current = +""
        current_width = 0

        str.split(/(\s+)/).each do |token|
          token_width = display_width(token)

          if current_width + token_width <= max_width
            current << token
            current_width += token_width
          elsif current_width.zero?
            # Single token wider than max — force it on its own line
            lines << token
          else
            lines << current.rstrip
            token = token.lstrip
            current = +token
            current_width = display_width(token)
          end
        end

        lines << current.rstrip unless current.strip.empty?
        lines
      end

      def strip_ansi(str)
        str.gsub(/\e\[[0-9;]*m/, "")
      end

      def display_width(str)
        Unicode::DisplayWidth.of(str)
      end
    end
  end
end
