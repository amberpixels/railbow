# frozen_string_literal: true

module Railbow
  # Assigns maximally-spaced colors to a set of unique labels.
  #
  # Instead of hashing into a fixed palette (where two labels can collide
  # onto adjacent colors), this assigns colors by rank — evenly spacing
  # hues around the color wheel. Two labels always get maximally different
  # colors, three labels get ~120 deg apart, etc.
  #
  # Usage:
  #   assigner = Railbow::ColorAssigner.new(["Alice", "Bob", "Carol"])
  #   assigner.color_for("Alice")  # => "\e[38;5;174m"
  #   assigner.code_for("Bob")     # => 116  (256-color code)
  #
  class ColorAssigner
    # Soft/muted 256-color codes arranged around the hue wheel.
    # 12 stops, evenly spaced in hue, all at moderate saturation/lightness
    # so they look pleasant on dark terminals.
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

    # Returns the 256-color ANSI escape for the given label.
    def color_for(label)
      code = code_for(label)
      "\e[38;5;#{code}m"
    end

    # Returns just the 256-color code integer for the given label.
    def code_for(label)
      @mapping[label] || WHEEL[0]
    end
  end
end
