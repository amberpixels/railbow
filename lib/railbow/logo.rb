# frozen_string_literal: true

module Railbow
  LOGO_SEGMENTS = [
    ["░█▀▀█", "░█▀▀█", "▀█▀", "░█───", "░█▀▀█", "░█▀▀▀█", "░█───░█"],
    ["░█▄▄▀", "░█▄▄█", "░█─", "░█───", "░█▀▀▄", "░█──░█", "░█─█─░█"],
    ["░█─░█", "░█─░█", "▄█▄", "░█▄▄█", "░█▄▄█", "░█▄▄▄█", "─░█░█─"]
  ].freeze

  LOGO_COLORS = [
    "\e[38;5;196m", "\e[38;5;208m", "\e[38;5;220m",
    "\e[38;5;40m", "\e[38;5;33m", "\e[38;5;93m", "\e[38;5;163m"
  ].freeze

  RESET = "\e[0m"

  def self.print_logo
    LOGO_SEGMENTS.each do |segments|
      print " "
      segments.each_with_index do |seg, i|
        print "#{LOGO_COLORS[i]}#{seg}#{RESET}"
        print " " unless i == segments.length - 1
      end
      puts
    end
  end
end
