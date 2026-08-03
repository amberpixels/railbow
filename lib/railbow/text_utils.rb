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

    # ANSI-aware counterpart to truncate_str: escape codes pass through
    # unmeasured, and a color left open at the cut is closed before the
    # ellipsis so it cannot leak into whatever follows the cell.
    def truncate_ansi(str, max_width)
      s = str.to_s
      return s if display_width(strip_ansi(s)) <= max_width

      result = +""
      width = 0
      open_color = false
      i = 0
      while i < s.length
        if s[i] == "\e" && (close = s.index("m", i))
          code = s[i..close]
          result << code
          open_color = (code != "\e[0m")
          i = close + 1
        else
          ch = s[i]
          ch_width = display_width(ch)
          break if width + ch_width > max_width - 3
          result << ch
          width += ch_width
          i += 1
        end
      end
      result << "\e[0m" if open_color
      "#{result}..."
    end
  end
end
