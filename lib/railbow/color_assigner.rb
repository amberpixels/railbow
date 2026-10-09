# frozen_string_literal: true

module Railbow
  # Spreads a set of labels evenly around the color wheel by rank. Hashing
  # into a palette could land two labels on neighboring colors; by rank, two
  # labels sit opposite each other, three about 120 deg apart, and so on.
  #
  #   assigner = Railbow::ColorAssigner.new(["Alice", "Bob", "Carol"])
  #   assigner.color_for("Alice")  # => "\e[38;5;174m"
  #   assigner.code_for("Bob")     # => 116  (256-color code)
  #
  class ColorAssigner
    # Muted 256-color codes in hue order, at moderate saturation and
    # lightness so they sit well on dark terminals.
    WHEEL = [
      174, # 0°   coral / muted rose
      216, # 30°  peach
      180, # 60°  warm sand
      150, # 120° sage green
      116, # 160° soft teal
      117, # 200° soft sky blue
      111, # 220° periwinkle
      146, # 260° lavender
      176, # 300° soft magenta
      182  # 330° dusty pink
    ].freeze

    def initialize(labels)
      sorted = labels.uniq.sort
      @mapping = {}
      sorted.each_with_index do |label, idx|
        wheel_idx = (idx * WHEEL.size / [sorted.size, 1].max) % WHEEL.size
        @mapping[label] = WHEEL[wheel_idx]
      end
    end

    def color_for(label)
      code = code_for(label)
      "\e[38;5;#{code}m"
    end

    # An unknown label gets the first color.
    def code_for(label)
      @mapping[label] || WHEEL[0]
    end
  end
end
