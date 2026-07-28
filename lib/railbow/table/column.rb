# frozen_string_literal: true

module Railbow
  module Table
    class Column
      attr_reader :label, :width, :min_width, :max_width, :align, :truncate, :truncate_fn, :sticky, :accent

      # accent: the column carries its own meaning through color (a status
      # glyph, say), so it keeps that color when the row is dimmed.
      def initialize(label:, width: :auto, min_width: nil, max_width: nil, align: :left, truncate: false, truncate_fn: nil, sticky: false, accent: false)
        @label = label
        @width = width
        @min_width = min_width
        @max_width = max_width
        @align = align
        @truncate = truncate
        @truncate_fn = truncate_fn
        @sticky = sticky
        @accent = accent
      end

      def fixed?
        width.is_a?(Integer)
      end
    end
  end
end
