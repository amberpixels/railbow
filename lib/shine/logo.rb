# Each line split into 7 letter segments + spacing
LOGO = [
  ["░█▀▀█", "░█▀▀█", "▀█▀", "░█───", "░█▀▀█", "░█▀▀▀█", "░█───░█"],
  ["░█▄▄▀", "░█▄▄█", "░█─", "░█───", "░█▀▀▄", "░█──░█", "░█─█─░█"],
  ["░█─░█", "░█─░█", "▄█▄", "░█▄▄█", "░█▄▄█", "░█▄▄▄█", "─░█░█─"]
]

# Rainbow colors: Red, Orange, Yellow, Green, Blue, Indigo, Violet
COLORS = [
  "\e[38;5;196m", # R - red
  "\e[38;5;208m", # A - orange
  "\e[38;5;220m", # I - yellow
  "\e[38;5;40m",  # L - green
  "\e[38;5;33m",  # B - blue
  "\e[38;5;93m",  # O - indigo
  "\e[38;5;163m"  # W - violet
]
RESET = "\e[0m"

def print_logo
  LOGO.each do |segments|
    print " "
    segments.each_with_index do |seg, i|
      print "#{COLORS[i]}#{seg}#{RESET}"
      print " " unless i == segments.length - 1
    end
    puts
  end
end

print_logo
