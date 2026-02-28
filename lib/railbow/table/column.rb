# frozen_string_literal: true

module Railbow
  module Table
    class Column
      attr_reader :label, :width, :min_width, :max_width, :align, :truncate, :truncate_fn

      def initialize(label:, width: :auto, min_width: nil, max_width: nil, align: :left, truncate: false, truncate_fn: nil)
        @label = label
        @width = width
        @min_width = min_width
        @max_width = max_width
        @align = align
        @truncate = truncate
        @truncate_fn = truncate_fn
      end

      def fixed?
        width.is_a?(Integer)
      end
    end
  end
end
