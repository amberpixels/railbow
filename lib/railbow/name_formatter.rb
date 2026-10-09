# frozen_string_literal: true

module Railbow
  # Formats person names with a pattern language modeled on date formats.
  #
  # Tokens (the letter count is the length; 4 or more means the full word):
  #   F / FF / FFF / FFFF+   first name (1 char, 2 chars, 3 chars, full)
  #   L / LL / LLL / LLLL+   last name
  #   M / MM / MMM / MMMM+   middle name(s)
  #
  # Any other characters (spaces, dots, commas) are literals and pass through.
  #
  # Named presets:
  #   "initials"        => "F L"
  #   "short"           => "FF L"
  #   "first_name"      => "FFFF"
  #   "last_name"       => "LLLL"
  #   "full_name"       => "FFFF MMMM LLLL"
  #   "full_name_short" => "FFFF L."
  module NameFormatter
    PRESETS = {
      "initials" => "F L",
      "short" => "FF L",
      "first_name" => "FFFF",
      "last_name" => "LLLL",
      "full_name" => "FFFF MMMM LLLL",
      "full_name_short" => "FFFF L."
    }.freeze

    TOKEN_RE = /([FLM])\1*/
    # Sentinel inserted when a token expands to empty, so surrounding
    # literals that only make sense next to a value can be cleaned up.
    EMPTY = "\x00"

    module_function

    # Formats a name by a pattern or preset name. "" for a nil or empty name.
    def format(name, pattern)
      return "" if name.nil? || name.empty?

      pattern = PRESETS.fetch(pattern, pattern)
      parts = name.split(/[\s._-]+/)

      first = parts.first || ""
      last = (parts.size > 1) ? parts.last : ""
      middle = (parts.size > 2) ? parts[1..-2] : []

      result = pattern.gsub(TOKEN_RE) do |match|
        letter = match[0]
        len = match.length

        expanded = case letter
        when "F" then truncate(first, len)
        when "L" then truncate(last, len)
        when "M" then middle.map { |m| truncate(m, len) }.join(" ")
        end

        expanded.empty? ? EMPTY : expanded
      end

      # A missing part takes its adjacent literals with it, so "F L." on a
      # one-word name gives no stray dot.
      result.gsub(/[^a-zA-Z\x00]*\x00[^a-zA-Z\x00]*/, " ")
        .gsub(/  +/, " ")
        .strip
    end

    # A full word keeps its case; a cut one is capitalized.
    def truncate(word, len)
      return "" if word.nil? || word.empty?

      if len >= 4 || len >= word.length
        word
      else
        word[0, len].capitalize
      end
    end

    private_class_method :truncate
  end
end
