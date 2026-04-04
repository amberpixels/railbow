# frozen_string_literal: true

require "unicode/display_width"

module Railbow
  module TextUtils
    def strip_ansi(str)
      str.to_s.gsub(/\e\[[0-9;]*m/, "")
    end

    def display_width(str)
      Unicode::DisplayWidth.of(str.to_s)
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
  end
end
