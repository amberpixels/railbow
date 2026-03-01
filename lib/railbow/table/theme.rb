# frozen_string_literal: true

module Railbow
  module Table
    class Theme
      attr_reader :col_separator, :tick_separator, :tick_cross_separator,
        :header_col_separator, :cell_padding,
        :format_header_cell, :format_separator

      def initialize(col_separator:, header_col_separator:, cell_padding:,
        format_header_cell:, format_separator: nil, tick_separator: nil, tick_cross_separator: nil)
        @col_separator = col_separator
        @tick_separator = tick_separator || col_separator
        @tick_cross_separator = tick_cross_separator || @tick_separator
        @header_col_separator = header_col_separator
        @cell_padding = cell_padding
        @format_header_cell = format_header_cell
        @format_separator = format_separator
      end
    end

    module Themes
      RESET = "\e[0m"
      BOLD = "\e[1m"
      WHITE = "\e[97m"
      PURPLE = "\e[38;5;141m"
      BG_PURPLE = "\e[48;5;99m"
      DIM = "\e[2m"

      WALLS = Theme.new(
        col_separator: "\u2502",
        tick_separator: "\u252c",
        tick_cross_separator: "\u253c",
        header_col_separator: " ",
        cell_padding: " ",
        format_header_cell: ->(text, _padding) {
          "#{BG_PURPLE}#{BOLD}#{WHITE}#{text}#{RESET}"
        },
        format_separator: ->(label) {
          "#{PURPLE}#{label}#{RESET}"
        }
      )

      PLAIN = Theme.new(
        col_separator: " ",
        header_col_separator: " ",
        cell_padding: "",
        format_header_cell: ->(text, _padding) {
          "#{BOLD}#{text}#{RESET}"
        }
      )
    end
  end
end
