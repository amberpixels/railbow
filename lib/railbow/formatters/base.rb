# frozen_string_literal: true

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

      def diff_tag_branch(name) = "\e[38;5;39m● #{name}#{RESET}"
      def diff_tag_uncommitted = "\e[38;5;220m● new#{RESET}"

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

      def format_relative_time(timestamp)
        ts = timestamp.to_s
        return ts if ts.length != 14

        time = Time.new(
          ts[0..3].to_i, ts[4..5].to_i, ts[6..7].to_i,
          ts[8..9].to_i, ts[10..11].to_i, ts[12..13].to_i
        )
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

      def strip_ansi(str)
        str.gsub(/\e\[[0-9;]*m/, "")
      end

      def display_width(str)
        Unicode::DisplayWidth.of(str)
      end
    end
  end
end
