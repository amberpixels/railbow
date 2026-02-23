# frozen_string_literal: true

require "io/console"
require "unicode/display_width"
require "zlib"

module Railbow
  module Formatters
    class Base
      RESET = "\e[0m"
      BOLD = "\e[1m"
      GREEN = "\e[32m"
      YELLOW = "\e[33m"
      RED = "\e[31m"
      CYAN = "\e[36m"
      DIM = "\e[2m"
      PURPLE = "\e[38;5;141m"
      BG_PURPLE = "\e[48;5;99m"
      WHITE = "\e[97m"

      TABLE_PALETTE = [
        196, # red
        208, # orange
        220, # yellow
        76,  # green
        48,  # mint
        39,  # cyan
        33,  # blue
        63,  # indigo
        129, # purple
        170, # pink
        214, # amber
        109  # teal
      ].freeze

      BRIGHT_WHITE = "\e[1;97m"

      def dim(str) = "#{DIM}#{str}#{RESET}"
      def bright_white(str) = "#{BRIGHT_WHITE}#{str}#{RESET}"
      def green(str) = "#{GREEN}#{str}#{RESET}"
      def yellow(str) = "#{YELLOW}#{str}#{RESET}"
      def red(str) = "#{RED}#{str}#{RESET}"
      def cyan(str) = "#{CYAN}#{str}#{RESET}"
      def bold(str) = "#{BOLD}#{str}#{RESET}"
      def green_bold(str) = "#{GREEN}#{BOLD}#{str}#{RESET}"
      def yellow_bold(str) = "#{YELLOW}#{BOLD}#{str}#{RESET}"

      def table_color(table_name)
        TABLE_PALETTE[Zlib.crc32(table_name.to_s) % TABLE_PALETTE.size]
      end

      def table_tag(table_name)
        color_code = table_color(table_name)
        "\e[38;5;#{color_code}m● #{table_name}#{RESET}"
      end

      def table_tags(table_names)
        return "" if table_names.nil? || table_names.empty?

        table_names.map { |t| table_tag(t) }.join(" ")
      end

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
        when :migrated then "✅"
        when :reverting then "⏪"
        when :reverted then "✅"
        when :check then "✓"
        when :status then "📊"
        else ""
        end
      end

      def format_timestamp(timestamp)
        ts = timestamp.to_s
        return ts if ts.length != 14

        "#{ts[0..3]}-#{ts[4..5]}-#{ts[6..7]} #{ts[8..9]}:#{ts[10..11]}:#{ts[12..13]}"
      end

      def render_table(header, rows, separators: {}, truncate_cols: {}, highlight_rows: Set.new)
        # Apply truncation to specified columns
        if truncate_cols.any?
          rows = rows.map do |row|
            row.each_with_index.map do |cell, i|
              truncate_cols.key?(i) ? truncate_str(cell.to_s, truncate_cols[i]) : cell
            end
          end
        end

        all_rows = [header] + rows
        last = header.size - 1

        # For non-last columns, measure max width across all rows.
        # For the last column, don't pad — it will be wrapped to terminal width.
        col_widths = header.each_index.map do |i|
          next 0 if i == last
          max = all_rows.map { |row| display_width(strip_ansi(row[i].to_s)) }.max
          truncate_cols.key?(i) ? [max, truncate_cols[i]].min : max
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

          last_cell_raw = row[last].to_s
          last_cell_plain = strip_ansi(last_cell_raw)
          prefix << "│"

          if last_col_max && display_width(last_cell_plain) > last_col_max
            blank_prefix = row[0...last].each_with_index.map { |_, i|
              " " * (col_widths[i] + 2)
            }.join("│")
            blank_prefix << "│"

            wrapped = ansi_word_wrap(last_cell_raw, last_col_max)
            prefix + " #{wrapped.first} \n" +
              wrapped[1..].map { |line| "#{blank_prefix} #{line} " }.join("\n")
          else
            prefix + " #{last_cell_raw} "
          end
        }

        fmt_header = ->(row) {
          row.each_with_index.map { |cell, i|
            s = cell.to_s
            padding = (i == last) ? "" : " " * (col_widths[i] - display_width(strip_ansi(s)))
            " #{BG_PURPLE}#{BOLD}#{WHITE}#{s}#{padding}#{RESET} "
          }.join(" ")
        }

        lines = []
        lines << fmt_header.call(header)
        rows.each_with_index do |row, i|
          if separators.key?(i)
            lines << month_separator(separators[i])
          end
          formatted = fmt_row.call(row)
          formatted = highlight_row(formatted) if highlight_rows.include?(i)
          lines << formatted
        end
        lines.join("\n")
      end

      private

      def truncate_str(str, max_width)
        return str if display_width(strip_ansi(str)) <= max_width

        plain = strip_ansi(str)
        truncated = +""
        width = 0
        plain.each_char do |ch|
          ch_width = display_width(ch)
          break if width + ch_width > max_width - 3
          truncated << ch
          width += ch_width
        end
        "#{truncated}..."
      end

      def highlight_row(str)
        # Wrap in WHITE; existing ANSI codes (status colors, table tags) override it,
        # and WHITE resumes after each RESET. Keep │ borders in terminal default.
        str
          .gsub(RESET, "#{RESET}#{WHITE}")
          .gsub("│", "#{RESET}│#{WHITE}")
          .then { |s| "#{WHITE}#{s}#{RESET}" }
      end

      def month_separator(label)
        "  #{DIM}───#{RESET}  #{PURPLE}#{label}#{RESET}  #{DIM}───#{RESET}"
      end

      def terminal_width
        return $stdout.winsize[1] if $stdout.respond_to?(:winsize) && $stdout.tty?
        nil
      rescue
        nil
      end

      def ansi_word_wrap(str, max_width)
        plain = strip_ansi(str)
        plain_lines = word_wrap(plain, max_width)

        # Map each plain line back to the ANSI string by walking through
        # the original and consuming visible chars line by line
        result = []
        pos = 0 # position in original str
        last_color = nil # track the last active color across lines
        plain_lines.each do |plain_line|
          target = plain_line.lstrip
          line = +""
          line << last_color if last_color
          visible_consumed = 0
          skipping_leading = true

          while pos < str.length && visible_consumed < display_width(target)
            if str[pos] == "\e"
              # Consume full ANSI escape
              esc_end = str.index("m", pos) || pos
              code = str[pos..esc_end]
              line << code
              last_color = (code == RESET) ? nil : code
              pos = esc_end + 1
            else
              ch = str[pos]
              unless skipping_leading && ch.match?(/\s/) && visible_consumed == 0
                skipping_leading = false
                line << ch
                visible_consumed += display_width(ch)
              end
              pos += 1
            end
          end

          # Consume any trailing ANSI codes attached to this segment
          while pos < str.length && str[pos] == "\e"
            esc_end = str.index("m", pos) || pos
            code = str[pos..esc_end]
            line << code
            last_color = (code == RESET) ? nil : code
            pos = esc_end + 1
          end

          result << line
        end

        result
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
