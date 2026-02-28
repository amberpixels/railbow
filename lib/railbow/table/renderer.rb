# frozen_string_literal: true

require "io/console"
require "unicode/display_width"

module Railbow
  module Table
    class Renderer
      RESET = "\e[0m"
      WHITE = "\e[97m"

      attr_reader :columns, :theme

      def initialize(columns:, theme:)
        @columns = columns
        @theme = theme
      end

      def render(rows, separators: {}, highlight_rows: Set.new, tick_rows: Set.new, tick_col: nil)
        return "" if columns.empty?

        # Pre-truncate non-last columns that have truncate + max_width
        rows = rows.map { |row|
          row.each_with_index.map { |cell, i|
            col = columns[i]
            if col&.truncate && col.max_width && i < columns.size - 1
              truncate_str(cell.to_s, col.max_width)
            else
              cell
            end
          }
        }

        resolved = resolve_widths(rows)
        lines = []
        lines << render_header(resolved)
        rows.each_with_index do |row, i|
          tc = (tick_rows.include?(i) && tick_col) ? tick_col : nil
          if separators.key?(i) && theme.format_separator
            sep_row = Array.new(columns.size, "")
            sep_row[1] = theme.format_separator.call(separators[i]) if columns.size > 1
            lines << render_row(sep_row, resolved, tick_col: tc, tick_cross: true)
            tc = nil # tick already shown on separator row
          end
          formatted = render_row(row, resolved, tick_col: tc)
          formatted = highlight_row_text(formatted) if highlight_rows.include?(i)
          lines << formatted
        end
        lines.join("\n")
      end

      private

      def resolve_widths(rows)
        all_rows = rows
        last = columns.size - 1

        columns.each_with_index.map do |col, i|
          if col.fixed?
            col.width
          elsif i == last
            # Last column: don't pad, will be wrapped if it overflows
            0
          else
            header_w = display_width(col.label)
            content_w = all_rows.map { |row| display_width(strip_ansi(row[i].to_s)) }.max || 0
            w = [header_w, content_w].max
            w = [w, col.min_width].max if col.min_width
            w = [w, col.max_width].min if col.max_width
            w
          end
        end
      end

      def render_header(widths)
        last = columns.size - 1
        pad = theme.cell_padding

        columns.each_with_index.map { |col, i|
          text = col.label
          padding = (i == last) ? "" : " " * (widths[i] - display_width(text))
          cell = theme.format_header_cell.call("#{text}#{padding}", padding)
          "#{pad}#{cell}#{pad}"
        }.join(theme.header_col_separator)
      end

      def render_row(row, widths, tick_col: nil, tick_cross: false)
        last = columns.size - 1
        pad = theme.cell_padding
        default_sep = theme.col_separator
        tick_sep = tick_cross ? theme.tick_cross_separator : theme.tick_separator

        prefix_parts = row[0...last].each_with_index.map { |cell, i|
          s = cell.to_s
          cell_w = display_width(strip_ansi(s))
          padding = " " * [widths[i] - cell_w, 0].max
          content = (columns[i].align == :right) ? "#{padding}#{s}" : "#{s}#{padding}"
          "#{pad}#{content}#{RESET}#{pad}"
        }

        # Join prefix parts with per-position separators
        # Loop index i joins column i-1 and column i (separator_index = i-1)
        # For tick_col, flanking separator indices are tick_col-1 and tick_col
        prefix = prefix_parts.first.to_s
        (1...prefix_parts.size).each do |i|
          sep_idx = i - 1
          sep = (tick_col && (sep_idx == tick_col - 1 || sep_idx == tick_col)) ? tick_sep : default_sep
          prefix << "#{sep}#{prefix_parts[i]}"
        end

        last_cell_raw = row[last].to_s

        # Separator before the last column has index (last - 1)
        last_sep_idx = last - 1
        last_sep = (tick_col && (last_sep_idx == tick_col - 1 || last_sep_idx == tick_col)) ? tick_sep : default_sep
        render_last_cell(prefix, prefix_parts, last_cell_raw, widths, last, col_sep: last_sep)
      end

      def render_last_cell(prefix, prefix_parts, last_cell_raw, widths, last, col_sep: nil)
        pad = theme.cell_padding
        sep = col_sep || theme.col_separator

        # Truncate if configured via column settings
        if columns[last].truncate && columns[last].max_width
          last_cell_raw = truncate_str(last_cell_raw, columns[last].max_width)
        end

        last_cell_plain = strip_ansi(last_cell_raw)
        term_w = terminal_width
        prefix_width = compute_prefix_width(widths, last)
        last_col_max = term_w ? [term_w - prefix_width, 10].max : nil

        # Use custom truncate_fn if available (e.g. table tags with +N)
        if columns[last].truncate_fn && last_col_max &&
            display_width(last_cell_plain) > last_col_max
          last_cell_raw = columns[last].truncate_fn.call(last_cell_raw, last_col_max)
          return "#{prefix}#{sep}#{pad}#{last_cell_raw}#{RESET}#{pad}"
        end

        # Truncate to terminal width (by whole words) instead of wrapping
        if columns[last].truncate && !columns[last].max_width && last_col_max &&
            display_width(last_cell_plain) > last_col_max
          last_cell_raw = truncate_by_words(last_cell_raw, last_col_max)
          return "#{prefix}#{sep}#{pad}#{last_cell_raw}#{RESET}#{pad}"
        end

        if last_col_max && display_width(strip_ansi(last_cell_raw)) > last_col_max
          blank_prefix = prefix_parts.map { |part|
            " " * display_width(strip_ansi(part))
          }.join(sep)

          wrapped = ansi_word_wrap(last_cell_raw, last_col_max)
          "#{prefix}#{sep}#{pad}#{wrapped.first}#{RESET}#{pad}\n" +
            wrapped[1..].map { |line| "#{blank_prefix}#{sep}#{pad}#{line}#{RESET}#{pad}" }.join("\n")
        else
          "#{prefix}#{sep}#{pad}#{last_cell_raw}#{RESET}#{pad}"
        end
      end

      def compute_prefix_width(widths, last)
        pad_w = display_width(theme.cell_padding)
        sep_w = display_width(theme.col_separator)
        # Each non-last column: pad + content + pad, joined by separator
        total = 0
        (0...last).each do |i|
          total += pad_w + widths[i] + pad_w
        end
        # Separators between columns + trailing separator before last column
        total += sep_w * last
        # Plus pad on last column
        total += pad_w
        total
      end

      def highlight_row_text(str)
        str
          .gsub(RESET, "#{RESET}#{WHITE}")
          .gsub("\u2502", "#{RESET}\u2502#{WHITE}")
          .then { |s| "#{WHITE}#{s}#{RESET}" }
      end

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

      def truncate_by_words(str, max_width)
        return str if display_width(strip_ansi(str)) <= max_width

        segments = str.scan(/\S+\s*/)
        result = +""
        width = 0

        segments.each do |seg|
          seg_plain = strip_ansi(seg)
          seg_width = display_width(seg_plain)
          if width + seg_width + 3 > max_width && width > 0
            result.rstrip!
            result << "..."
            return result
          end
          result << seg
          width += seg_width
        end

        result
      end

      def terminal_width
        return $stdout.winsize[1] if $stdout.respond_to?(:winsize) && $stdout.tty?
        nil
      rescue
        nil
      end

      def strip_ansi(str)
        str.to_s.gsub(/\e\[[0-9;]*m/, "")
      end

      def display_width(str)
        Unicode::DisplayWidth.of(str.to_s)
      end

      def ansi_word_wrap(str, max_width)
        plain = strip_ansi(str)
        plain_lines = word_wrap(plain, max_width)

        result = []
        pos = 0
        last_color = nil
        plain_lines.each do |plain_line|
          target = plain_line.lstrip
          line = +""
          line << last_color if last_color
          visible_consumed = 0
          skipping_leading = true

          while pos < str.length && visible_consumed < display_width(target)
            if str[pos] == "\e"
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
            # Single token wider than max — try to break on underscores
            broken = break_long_token(token, max_width)
            lines.concat(broken[0...-1])
            current = +broken.last
            current_width = display_width(current)
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

      def break_long_token(token, max_width)
        return [token] unless token.include?("_")

        parts = token.split(/(?<=_)/) # split keeping _ at end of each part
        lines = []
        current = +""
        current_width = 0

        parts.each do |part|
          part_width = display_width(part)
          if current_width + part_width <= max_width
            current << part
            current_width += part_width
          elsif current_width.zero?
            lines << part
          else
            lines << current
            current = +part
            current_width = part_width
          end
        end

        lines << current unless current.empty?
        lines.empty? ? [token] : lines
      end
    end
  end
end
