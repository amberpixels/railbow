# frozen_string_literal: true

require "zlib"
require_relative "../clock"
require_relative "../text_utils"

module Railbow
  module Formatters
    class Base
      include TextUtils

      RESET = "\e[0m"
      BOLD = "\e[1m"
      GREEN = "\e[32m"
      YELLOW = "\e[33m"
      RED = "\e[31m"
      CYAN = "\e[36m"
      DIM = "\e[2m"
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

      # Narrowest name a tagged cell will accept before the tags are dropped.
      NAME_TAGS_FLOOR = 12

      # One tag: its color, a glyph (plus a worktree mark or a space), a label,
      # and its closing code (a reset, or the ghost foreground on a ghost row).
      TAG_PARTS = /\A(\e\[[\d;]*m)(.ₜ?\s?)([^\e]*)(\e\[[\d;]*m)\z/
      TAG_RUN = /\e\[[\d;]*m[^\e]*\e\[[\d;]*m/

      # A branch named <TASK-ID>/<slug>: the id is what identifies the work.
      TASK_ID_PREFIX = /\A[A-Z][A-Z0-9]*-\d+\//

      def dim(str) = "#{DIM}#{str}#{RESET}"
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

      def diff_tag_branch(name) = "\e[38;5;39m\u2387 #{name}#{RESET}"
      def diff_tag_merging(name) = "\e[38;5;213m\u2B07 #{name}#{RESET}"

      def landed_tag(date, fresh: false)
        color = fresh ? "\e[38;5;220m" : DIM
        "#{color}↪ #{date.strftime("%b %d")}#{RESET}"
      end

      def table_tag(table_name)
        color_code = table_color(table_name)
        "\e[38;5;#{color_code}m● #{table_name}#{RESET}"
      end

      def table_tags(table_names)
        return "" if table_names.nil? || table_names.empty?

        table_names.map { |t| table_tag(t) }.join(" ")
      end

      # Re-fits a formatted table_tags string within max_width: as many whole
      # tags as fit plus "+N" for the rest, then one truncated tag, then "+N".
      def table_tags_fitted(formatted_str, max_width)
        return formatted_str if formatted_str.nil? || formatted_str.empty?

        # Each tag is "\e[38;5;NNNm● name\e[0m"
        segments = formatted_str.scan(/\e\[38;5;\d+m● [^\e]+\e\[0m/)
        return formatted_str if segments.empty?

        total = segments.size
        plain_segments = segments.map { |s| strip_ansi(s) }

        return formatted_str if display_width(plain_segments.join(" ")) <= max_width

        (total - 1).downto(1) do |count|
          remaining = total - count
          suffix = " +#{remaining}"
          candidate = plain_segments[0...count].join(" ") + suffix
          if display_width(candidate) <= max_width
            return segments[0...count].join(" ") + suffix
          end
        end

        # A truncated first tag needs 7 columns at least: "● t… +N"
        if max_width >= 7
          suffix = (total > 1) ? " +#{total - 1}" : ""
          avail = max_width - display_width(suffix)
          if avail >= 4 # "● " (2) + at least 1 char + "…" (1)
            first_plain = plain_segments[0] # e.g. "● some_table"
            name_part = first_plain.sub(/^● /, "")
            name_max = avail - 2 - 1
            truncated_name = name_part[0, name_max]
            color_match = segments[0].match(/\e\[38;5;\d+m/)
            color = color_match ? color_match[0] : ""
            return "#{color}● #{truncated_name}…#{RESET}#{suffix}"
          end
        end

        "+#{total}"
      end

      # Re-fits a Migration Name cell whose tags (branch, landed) sit flush
      # right. Cutting from the right would eat the tags and leave a bare
      # ellipsis, so the name gives up the space instead, down to
      # NAME_TAGS_FLOOR. Past that the tags are shortened, and dropped only
      # when even their shortest form does not fit.
      def name_with_tags_fitted(cell, max_width)
        str = cell.to_s
        return truncate_ansi(str, max_width) if display_width(strip_ansi(str)) <= max_width

        split = str.rindex(/\s{2,}\e\[/)
        return truncate_ansi(str, max_width) unless split

        # rindex stops at the last two spaces of the padding run, so the rest of
        # it still hangs off the name and would be truncated in place of it.
        name = str[0...split].rstrip
        tags = str[split..].lstrip
        tags_width = display_width(strip_ansi(tags))
        name_room = max_width - tags_width - 2
        if name_room < NAME_TAGS_FLOOR
          name_keep = [display_width(strip_ansi(name)), NAME_TAGS_FLOOR].min
          tags = fit_tags(tags, max_width - name_keep - 2)
          return truncate_ansi(name, max_width) unless tags

          tags_width = display_width(strip_ansi(tags))
          name_room = max_width - tags_width - 2
        end

        name = truncate_ansi(name, name_room)
        padding = max_width - display_width(strip_ansi(name)) - tags_width
        "#{name}#{" " * [padding, 2].max}#{tags}"
      end

      # Re-fits a space-joined run of tags within max_width, or nil when even
      # the shortest form does not fit. The last tag carries the free-form
      # label (branch, merge source), so it is shortened; tags before it are
      # dropped from the left once it is at its shortest.
      def fit_tags(tags, max_width)
        str = tags.to_s
        return str if display_width(strip_ansi(str)) <= max_width

        segments = str.scan(TAG_RUN)
        return nil unless segments.join(" ") == str

        *rest, last = segments
        loop do
          rest_width = rest.empty? ? 0 : display_width(strip_ansi(rest.join(" "))) + 1
          fitted = shorten_tag(last, max_width - rest_width)
          return [*rest, fitted].join(" ") if fitted
          return nil if rest.empty?

          rest.shift
        end
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

      def format_date(timestamp, mode = "full")
        ts = timestamp.to_s
        time = Railbow::Clock.from_version(ts)
        return ts unless time

        case mode
        when "full"
          time.strftime("%Y-%m-%d %H:%M:%S")
        when "rel"
          format_relative_time_from(time)
        when "short"
          time.strftime("%b %-d")
        when /\Acustom\((.+)\)\z/
          time.strftime($1)
        else
          time.strftime("%Y-%m-%d %H:%M:%S")
        end
      end

      def format_relative_time_from(time)
        diff = Time.now - time
        return "just now" if diff < 0

        minutes = diff.to_i / 60
        hours = minutes / 60
        days = hours / 24
        weeks = days / 7
        months = days / 30
        years = days / 365

        if minutes < 1 then "just now"
        elsif hours < 1 then "~#{minutes}min ago"
        elsif days < 1 then "~#{hours}hr ago"
        elsif weeks < 1 then "~#{days}d ago"
        elsif months < 1 then "~#{weeks}w ago"
        elsif years < 1 then "~#{months}mo ago"
        else "~#{years}y ago"
        end
      end

      private

      # Cuts one tag's label to fit max_width, keeping a task-id prefix whole,
      # and rebuilds it from its own codes: truncate_ansi would close it with a
      # reset and end a ghost row's foreground at the tag.
      def shorten_tag(tag, max_width)
        lead, glyph, label, close = tag.match(TAG_PARTS)&.captures
        return nil unless lead
        return tag if display_width(glyph + label) <= max_width

        label_room = max_width - display_width(glyph) - 1
        keep = label[TASK_ID_PREFIX] || label[0].to_s
        return nil if label.empty? || label_room < display_width(keep)

        cut = +""
        label.each_char do |ch|
          break if display_width(cut + ch) > label_room
          cut << ch
        end
        "#{lead}#{glyph}#{cut}…#{close}"
      end
    end
  end
end
