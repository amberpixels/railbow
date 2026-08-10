# frozen_string_literal: true

require "io/console"
require_relative "../text_utils"

module Railbow
  module Table
    class Renderer
      include TextUtils

      RESET = "\e[0m"
      WHITE = "\e[97m"
      GHOST_BG = "\e[48;5;52m"    # deep red/maroon background - stands out as abnormal
      GHOST_FG = "\e[38;5;217m"   # warm pink foreground for contrast
      DIMMED_FG = "\e[38;5;242m"  # muted grey - a row that is not currently in effect

      # The flexing last column never gets less than this from the terminal.
      MIN_LAST_COL = 10
      # Default floor for shrinkable columns that name no shrink_floor.
      MIN_SHRINK_WIDTH = 16

      attr_reader :columns, :theme

      # min_widths raises the resolved width of each column to at least the
      # given value, which is how several tables rendered in one run line their
      # columns up with each other. An explicit compact maxw still wins.
      #
      # term_width overrides the detected terminal width; render re-invokes
      # itself through a reduced renderer when the budget drops a column, and
      # the width it fits must be the same one this instance measured.
      def initialize(columns:, theme:, compact: {}, aliases: {}, min_widths: nil, term_width: nil)
        @compact = compact
        @aliases = aliases
        @min_widths = min_widths
        @term_width = term_width
        @reverse_col_aliases = aliases[:columns]&.invert || {}
        @columns = apply_hidden_columns(columns)
        @theme = theme
      end

      # The widths this table would resolve to on its own. Callers rendering
      # several tables together take the per-column maximum and feed it back as
      # min_widths.
      def column_widths(rows)
        return [] if columns.empty?

        resolve_widths(prepare_rows(rows))
      end

      # Width of everything left of the last column. The last column flexes to
      # the terminal, so this is where furniture drawn around the table (a
      # section rule, say) can stop without running past it.
      def fixed_width(widths)
        return 0 if columns.empty? || widths.nil? || widths.empty?

        compute_prefix_width(widths, columns.size - 1)
      end

      def render(rows, separators: {}, highlight_rows: Set.new, ghost_rows: Set.new, dim_rows: Set.new, tick_rows: Set.new, tick_col: nil)
        return "" if columns.empty?

        rows = prepare_rows(rows)

        # Width budget: when even fully shrunk columns cannot bring the table
        # under the terminal width, sacrifice the most expendable column and
        # render without it. One column per pass - the reduced renderer asks
        # again with what is left.
        if (drop = drop_index_to_fit(rows))
          return dropped_renderer(drop).render(
            rows.map { |row| row.reject.with_index { |_, i| i == drop } },
            separators: separators, highlight_rows: highlight_rows, ghost_rows: ghost_rows,
            dim_rows: dim_rows, tick_rows: tick_rows, tick_col: shift_tick_col(tick_col, drop)
          )
        end

        resolved = resolve_widths(rows)
        shrink_to_fit!(resolved, rows)

        # In oneline mode, truncate non-sticky non-last columns at resolved width
        if @compact[:oneline]
          rows = rows.map { |row|
            row.each_with_index.map { |cell, i|
              col = columns[i]
              if col && i < columns.size - 1 && !col.sticky && !col.truncate
                truncate_str(cell.to_s, resolved[i])
              else
                cell
              end
            }
          }
        end
        lines = []
        lines << render_header(resolved) unless @compact[:noheader]
        rows.each_with_index do |row, i|
          tc = (tick_rows.include?(i) && tick_col) ? tick_col : nil
          if separators.key?(i) && theme.format_separator
            lines << render_separator_row(separators[i], resolved, tick_col: tc)
            tc = nil # tick already shown on separator row
          end
          formatted = render_row(row, resolved, tick_col: tc, highlight: highlight_rows.include?(i),
            ghost: ghost_rows.include?(i), dim: dim_rows.include?(i))
          lines << formatted
        end
        lines.join("\n")
      end

      private

      # Everything that changes a cell's content, and therefore its width,
      # before widths are resolved: hidden columns, value aliases, and the
      # pre-truncation of non-last columns that cap themselves.
      def prepare_rows(rows)
        rows = remap_rows(rows) if @hidden_indices&.any?
        rows = apply_value_aliases(rows) if @aliases[:values]&.any?

        rows.map { |row|
          row.each_with_index.map { |cell, i|
            col = columns[i]
            if col&.truncate && col.max_width && i < columns.size - 1
              truncate_str(cell.to_s, col.max_width)
            else
              cell
            end
          }
        }
      end

      def resolve_widths(rows)
        all_rows = rows
        last = columns.size - 1
        global_maxw = @compact[:maxw]

        columns.each_with_index.map do |col, i|
          if col.fixed?
            w = col.width
          elsif i == last
            # Last column: don't pad, will be wrapped if it overflows
            w = 0
          else
            header_w = display_width(effective_label(col))
            content_w = all_rows.map { |row| display_width(strip_ansi(row[i].to_s)) }.max || 0
            w = [header_w, content_w].max
            w = [w, col.min_width].max if col.min_width
            w = [w, col.max_width].min if col.max_width
          end
          # Alignment across tables raises the width; an explicit maxw caps it
          # afterwards, so the user's cap stays authoritative.
          w = [w, @min_widths[i].to_i].max if @min_widths && i != last && w > 0
          w = [w, global_maxw].min if global_maxw && i != last && w > 0
          w
        end
      end

      def render_header(widths)
        last = columns.size - 1
        pad = effective_padding

        columns.each_with_index.map { |col, i|
          text = effective_label(col)
          padding = (i == last) ? "" : " " * [widths[i] - display_width(text), 0].max
          cell = theme.format_header_cell.call("#{text}#{padding}", padding)
          "#{pad}#{cell}#{pad}"
        }.join(theme.header_col_separator)
      end

      # A separator row is furniture, not data: the walls are drawn empty and the
      # label is laid over them starting at the second column. Writing over the
      # blanks rather than filling a cell means a label wider than its column
      # spills into the empty space to its right instead of shifting the row.
      def render_separator_row(label, widths, tick_col: nil)
        pad = effective_padding
        cells = widths.map { |w| "#{pad}#{" " * w}#{pad}" }

        skeleton = cells.first.to_s.dup
        (1...cells.size).each do |i|
          skeleton << "#{separator_at(i - 1, tick_col, cross: true)}#{cells[i]}"
        end
        return skeleton if cells.size < 2 || label.nil? || label.empty?

        offset = display_width(cells[0]) + display_width(separator_at(0, tick_col, cross: true)) + display_width(pad)
        tail = skeleton[(offset + display_width(label))..] || ""
        "#{skeleton[0, offset]}#{theme.format_separator.call(label)}#{tail}"
      end

      # The separator character between column index and index + 1. Columns
      # flanking the tick column get the tick variant so the week line reads
      # as one continuous rule.
      def separator_at(index, tick_col, cross: false)
        flanks_tick = tick_col && (index == tick_col - 1 || index == tick_col)
        return theme.col_separator unless flanks_tick

        cross ? theme.tick_cross_separator : theme.tick_separator
      end

      def render_row(row, widths, tick_col: nil, highlight: false, ghost: false, dim: false)
        last = columns.size - 1
        pad = effective_padding

        prefix_parts = row[0...last].each_with_index.map { |cell, i|
          s = cell.to_s
          cell_w = display_width(strip_ansi(s))
          padding = " " * [widths[i] - cell_w, 0].max
          content = (columns[i].align == :right) ? "#{padding}#{s}" : "#{s}#{padding}"
          content = style_cell(content, highlight: highlight, ghost: ghost, dim: dim, accent: columns[i].accent)
          "#{pad}#{content}#{RESET}#{pad}"
        }

        # Join prefix parts with per-position separators.
        # Loop index i joins column i-1 and column i (separator index = i-1).
        # dup: appending to prefix_parts.first itself would corrupt the parts
        # that render_last_cell measures for the wrapped-line indent.
        prefix = prefix_parts.first.to_s.dup
        (1...prefix_parts.size).each do |i|
          prefix << "#{separator_at(i - 1, tick_col)}#{prefix_parts[i]}"
        end

        last_cell_raw = row[last].to_s

        # Separator before the last column has index (last - 1)
        last_sep = separator_at(last - 1, tick_col)
        render_last_cell(prefix, prefix_parts, last_cell_raw, widths, last, col_sep: last_sep, highlight: highlight, ghost: ghost, dim: dim)
      end

      def render_last_cell(prefix, prefix_parts, last_cell_raw, widths, last, col_sep: nil, highlight: false, ghost: false, dim: false)
        pad = effective_padding
        sep = col_sep || theme.col_separator

        # Truncate if configured via column settings
        if columns[last].truncate && columns[last].max_width
          last_cell_raw = truncate_str(last_cell_raw, columns[last].max_width)
        end

        last_cell_plain = strip_ansi(last_cell_raw)
        term_w = terminal_width
        prefix_width = compute_prefix_width(widths, last)
        last_col_max = term_w ? [term_w - prefix_width - display_width(pad), MIN_LAST_COL].max : nil

        # Use custom truncate_fn if available (e.g. table tags with +N)
        if columns[last].truncate_fn && last_col_max &&
            display_width(last_cell_plain) > last_col_max
          last_cell_raw = columns[last].truncate_fn.call(last_cell_raw, last_col_max)
          last_cell_raw = style_cell(last_cell_raw, highlight: highlight, ghost: ghost, dim: dim, accent: columns[last].accent)
          return "#{prefix}#{sep}#{pad}#{last_cell_raw}#{RESET}#{pad}"
        end

        # Truncate to terminal width (by whole words) instead of wrapping
        if columns[last].truncate && !columns[last].max_width && last_col_max &&
            display_width(last_cell_plain) > last_col_max
          last_cell_raw = truncate_by_words(last_cell_raw, last_col_max)
          last_cell_raw = style_cell(last_cell_raw, highlight: highlight, ghost: ghost, dim: dim, accent: columns[last].accent)
          return "#{prefix}#{sep}#{pad}#{last_cell_raw}#{RESET}#{pad}"
        end

        # In oneline mode, truncate instead of wrapping
        if @compact[:oneline] && last_col_max && display_width(last_cell_plain) > last_col_max
          last_cell_raw = truncate_by_words(last_cell_raw, last_col_max)
          last_cell_raw = style_cell(last_cell_raw, highlight: highlight, ghost: ghost, dim: dim, accent: columns[last].accent)
          return "#{prefix}#{sep}#{pad}#{last_cell_raw}#{RESET}#{pad}"
        end

        last_cell_raw = style_cell(last_cell_raw, highlight: highlight, ghost: ghost, dim: dim, accent: columns[last].accent)

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

      def style_cell(content, highlight: false, ghost: false, dim: false, accent: false)
        if ghost
          "#{GHOST_BG}#{GHOST_FG}#{content}#{RESET}"
        elsif dim
          # An accent column keeps its color - on a dimmed row it is the one
          # cell still carrying meaning. Everything else drops its own colors:
          # one flat grey is what reads as "not in effect", and the resets that
          # end each inner color would break the grey run anyway.
          return content if accent

          "#{DIMMED_FG}#{strip_ansi(content)}#{RESET}"
        elsif highlight
          "#{WHITE}#{content}#{RESET}"
        else
          content
        end
      end

      def compute_prefix_width(widths, last)
        pad_w = display_width(effective_padding)
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
        return @term_width if @term_width
        return $stdout.winsize[1] if $stdout.respond_to?(:winsize) && $stdout.tty?
        nil
      rescue
        nil
      end

      # --- Width budget ---

      # The index of the column to sacrifice, or nil while shrinking alone can
      # still fit the table into the terminal.
      def drop_index_to_fit(rows)
        return nil unless terminal_width
        return nil if rows.empty?

        candidate = columns.each_index
          .select { |i| columns[i].droppable }
          .min_by { |i| columns[i].droppable }
        return nil unless candidate
        return nil if required_width(fully_shrunk_widths(rows), rows) <= terminal_width

        candidate
      end

      def dropped_renderer(drop)
        self.class.new(
          columns: columns.reject.with_index { |_, i| i == drop },
          theme: theme,
          compact: @compact,
          aliases: @aliases,
          min_widths: @min_widths&.reject&.with_index { |_, i| i == drop },
          term_width: terminal_width
        )
      end

      def shift_tick_col(tick_col, drop)
        return nil if tick_col.nil? || drop == tick_col

        (drop < tick_col) ? tick_col - 1 : tick_col
      end

      # Narrows shrinkable columns just enough to close the overflow, and
      # re-truncates their cells to the new width.
      def shrink_to_fit!(widths, rows)
        return if rows.empty? || !terminal_width

        overflow = required_width(widths, rows) - terminal_width
        return if overflow <= 0

        last = columns.size - 1
        columns.each_with_index do |col, i|
          break if overflow <= 0
          next if i == last || !col.shrinkable

          cut = [widths[i] - shrink_floor(col), overflow].min
          next if cut <= 0

          widths[i] -= cut
          overflow -= cut
          # A column that knows how to re-fit its own cells does it here: a
          # blind cut from the right would drop whatever the cell parked at its
          # far edge (right-aligned tags) instead of shortening the content.
          fit = col.truncate_fn || method(:truncate_ansi)
          rows.each { |row| row[i] = fit.call(row[i].to_s, widths[i]) }
        end
      end

      # Never below the header label: a column narrower than its own header
      # would push the header row out of alignment.
      def shrink_floor(col)
        [col.shrink_floor || MIN_SHRINK_WIDTH, display_width(effective_label(col))].max
      end

      def fully_shrunk_widths(rows)
        widths = resolve_widths(rows)
        last = columns.size - 1
        columns.each_with_index do |col, i|
          next if i == last || !col.shrinkable

          widths[i] = [widths[i], shrink_floor(col)].min
        end
        widths
      end

      # What the table needs from the terminal: every fixed column plus a
      # reserve for the flexing last column, which truncates down to
      # MIN_LAST_COL but never below it. The last column's header label counts
      # too - it is drawn as-is, so a label wider than every cell would poke
      # past the terminal edge otherwise.
      def required_width(widths, rows)
        last = columns.size - 1
        last_w = rows.map { |row| display_width(strip_ansi(row[last].to_s)) }.max || 0
        last_w = [last_w, display_width(effective_label(columns[last]))].max unless @compact[:noheader]
        compute_prefix_width(widths, last) + [last_w, MIN_LAST_COL].min + display_width(effective_padding)
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
            # Single token wider than max - try to break on underscores
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

      # --- Compact support ---

      def effective_padding
        @compact[:dense] ? "" : theme.cell_padding
      end

      def effective_label(col)
        col_aliases = @aliases[:columns]
        return col.label unless col_aliases

        col_aliases[col.label] || col.label
      end

      def apply_hidden_columns(columns)
        hidden = @compact[:hidden_columns]
        return columns unless hidden&.any?

        @hidden_indices = []
        filtered = []
        columns.each_with_index do |col, i|
          if hidden.any? { |h| h.downcase == col.label.downcase }
            @hidden_indices << i
          else
            filtered << col
          end
        end
        filtered
      end

      def remap_rows(rows)
        rows.map do |row|
          row.each_with_index.reject { |_, i| @hidden_indices.include?(i) }.map(&:first)
        end
      end

      def apply_value_aliases(rows)
        value_aliases = @aliases[:values]
        return rows unless value_aliases&.any?

        # Build column index → value alias map
        col_map = {}
        columns.each_with_index do |col, i|
          next unless col.aliased

          label = col.label
          col_map[i] = value_aliases[label] if value_aliases[label]
          # Also look up by original name if column was renamed by alias
          original = @reverse_col_aliases[label]
          col_map[i] = value_aliases[original] if original && value_aliases[original]
        end

        return rows if col_map.empty?

        rows.map do |row|
          row.each_with_index.map do |cell, i|
            aliases_for_col = col_map[i]
            if aliases_for_col
              apply_cell_alias(cell.to_s, aliases_for_col)
            else
              cell
            end
          end
        end
      end

      def apply_cell_alias(cell, aliases_for_col)
        plain = strip_ansi(cell)
        # Try exact match first, then prefix match for cells with appended indicators
        replacement = aliases_for_col[plain]
        if replacement
          cell.sub(plain) { replacement }
        else
          key = aliases_for_col.keys.find { |k| plain.start_with?(k) && plain[k.length..] =~ /\A\s/ }
          if key
            cell.sub(key) { aliases_for_col[key] }
          else
            cell
          end
        end
      end
    end
  end
end
