# frozen_string_literal: true

module Railbow
  # Formats person names using a pattern language inspired by date-format strings.
  #
  # Tokens (repeat the letter to control length; 4+ means full word):
  #   F / FF / FFF / FFFF+  — first name (1 char, 2 chars, … , full)
  #   L / LL / LLL / LLLL+  — last name
  #   M / MM / MMM / MMMM+  — middle name(s)
  #
  # Any other characters (spaces, dots, commas) are literals and pass through.
  #
  # Named presets:
  #   "initials"        → "F L"
  #   "short"           → "FF L"
  #   "first_name"      → "FFFF"
  #   "last_name"       → "LLLL"
  #   "full_name"       → "FFFF MMMM LLLL"
  #   "full_name_short" → "FFFF L."
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

    # Format a name according to a pattern or preset name.
    # Returns "" for nil/empty input.
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

      # Remove sentinels and any adjacent non-letter literals (dots, commas, spaces)
      result.gsub(/[^a-zA-Z\x00]*\x00[^a-zA-Z\x00]*/, " ")
        .gsub(/  +/, " ")
        .strip
    end

    # Truncate a word to `len` chars (4+ means full), preserving original case
    # for full words, capitalizing otherwise.
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
