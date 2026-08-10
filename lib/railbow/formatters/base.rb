# frozen_string_literal: true

require "zlib"
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

      # Re-fits a pre-formatted table_tags string within max_width,
      # showing full table names and "+N" for overflow.
      # Accepts the full formatted string (with ANSI) and splits it into segments.
      def table_tags_fitted(formatted_str, max_width)
        return formatted_str if formatted_str.nil? || formatted_str.empty?

        # Split into individual tag segments: each is "\e[38;5;NNNm● name\e[0m"
        segments = formatted_str.scan(/\e\[38;5;\d+m● [^\e]+\e\[0m/)
        return formatted_str if segments.empty?

        total = segments.size
        plain_segments = segments.map { |s| strip_ansi(s) }

        # Try fitting all tags
        return formatted_str if display_width(plain_segments.join(" ")) <= max_width

        # Try fitting progressively fewer tags with +N suffix
        (total - 1).downto(1) do |count|
          remaining = total - count
          suffix = " +#{remaining}"
          candidate = plain_segments[0...count].join(" ") + suffix
          if display_width(candidate) <= max_width
            return segments[0...count].join(" ") + suffix
          end
        end

        # Try fitting a truncated first table name + overflow.
        # Need at least 7 chars: "● t… +N" (dot + color prefix use no visible width beyond the dot)
        if max_width >= 7
          suffix = (total > 1) ? " +#{total - 1}" : ""
          # Available width for "● name…" part
          avail = max_width - display_width(suffix)
          # "● " prefix = 2 chars visible, plus at least 1 char of name + ellipsis (1 char)
          if avail >= 4 # "● " (2) + at least 1 char + "…" (1)
            first_plain = plain_segments[0] # e.g. "● some_table"
            name_part = first_plain.sub(/^● /, "")
            # Truncate name to fit: avail - 2 ("● ") - 1 ("…") = chars for name
            name_max = avail - 2 - 1
            truncated_name = name_part[0, name_max]
            color_match = segments[0].match(/\e\[38;5;\d+m/)
            color = color_match ? color_match[0] : ""
            return "#{color}● #{truncated_name}…#{RESET}#{suffix}"
          end
        end

        # Absolute fallback: just +N
        "+#{total}"
      end

      # Re-fits a Migration Name cell whose tags (branch, landed) were padded
      # flush against the right edge of a wider column. Truncating such a cell
      # from the right eats the tags whole and leaves a bare ellipsis floating
      # after the padding, so the name gives up the space instead and the tags
      # stay put. Below NAME_TAGS_FLOOR there is no room for both and the tags
      # are dropped outright - the name is what the row is about.
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
        return truncate_ansi(name, max_width) if name_room < NAME_TAGS_FLOOR

        name = truncate_ansi(name, name_room)
        padding = max_width - display_width(strip_ansi(name)) - tags_width
        "#{name}#{" " * [padding, 2].max}#{tags}"
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
        return ts if ts.length != 14

        time = begin
          Time.new(
            ts[0..3].to_i, ts[4..5].to_i, ts[6..7].to_i,
            ts[8..9].to_i, ts[10..11].to_i, ts[12..13].to_i
          )
        rescue ArgumentError
          return ts
        end

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

      private

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

      public
    end
  end
end
