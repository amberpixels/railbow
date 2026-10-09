# frozen_string_literal: true

require_relative "name_formatter"

module Railbow
  # Makes distinct names format distinctly by widening pattern tokens (F to
  # FFFF, then L) until no two collide. Names differing only in the middle
  # name count as one person and share an output.
  #
  #   NameCollisionResolver.resolve(["John Doe", "Jane Doe"], "F L")
  #   # => {"John Doe" => "Jo D", "Jane Doe" => "Ja D"}
  module NameCollisionResolver
    SUPERSCRIPTS = %w[² ³ ⁴ ⁵ ⁶ ⁷ ⁸ ⁹].freeze

    module_function

    # @param names [Array<String, nil>] raw author names (may contain duplicates/nils)
    # @param pattern [String] a NameFormatter pattern or preset name
    # @return [Hash{String => String}] raw name to disambiguated formatted name
    def resolve(names, pattern)
      pattern = NameFormatter::PRESETS.fetch(pattern, pattern)
      uniq_names = names.compact.reject(&:empty?).uniq

      canonical, aliases = merge_same_person(uniq_names)

      result = {}
      canonical.each { |n| result[n] = NameFormatter.format(n, pattern) }

      collisions = find_collisions(result)
      unless collisions.empty?
        tokens = parse_tokens(pattern)
        collisions.each do |_formatted, raw_names|
          resolve_group(raw_names, pattern, tokens, result)
        end
      end

      aliases.each { |variant, canon| result[variant] = result[canon] }

      result
    end

    # Groups names by first and last name; the shortest (no middle name) is
    # canonical. Returns [canonical_names, aliases], aliases mapping each
    # variant to its canonical name.
    def merge_same_person(names)
      groups = {}
      names.each do |name|
        parts = name.split(/[\s._-]+/)
        key = if parts.size >= 2
          [parts.first.downcase, parts.last.downcase]
        else
          [parts.first&.downcase, nil]
        end
        (groups[key] ||= []) << name
      end

      canonical = []
      aliases = {}
      groups.each_value do |group|
        canon = group.min_by(&:length)
        canonical << canon
        group.each { |name| aliases[name] = canon unless name == canon }
      end

      [canonical, aliases]
    end

    def find_collisions(mapping)
      mapping.group_by { |_raw, fmt| fmt }
        .select { |_fmt, pairs| pairs.size > 1 }
        .transform_values { |pairs| pairs.map(&:first) }
    end

    # Widens tokens, all F tokens before L, only for names that still collide:
    # a name that becomes unique keeps its shortest distinct form.
    def resolve_group(raw_names, base_pattern, base_tokens, result)
      remaining = raw_names.dup
      tokens = base_tokens.map(&:dup)

      expansion_order = tokens.each_index.sort_by { |i| (tokens[i][:type] == "F") ? 0 : 1 }

      expansion_order.each do |ti|
        tok = tokens[ti]
        next if tok[:maxed]

        until tok[:maxed]
          tok[:length] += 1
          tok[:maxed] = true if tok[:length] >= 4
          current_pattern = rebuild_pattern(tokens, base_pattern)

          remaining.each { |n| result[n] = NameFormatter.format(n, current_pattern) }

          # Within this group only, so one group's expansion never chases
          # collisions with another's.
          still_colliding = find_collisions(result.slice(*raw_names))
          if still_colliding.empty?
            remaining = []
            break
          end

          remaining = still_colliding.values.flatten
        end

        break if remaining.empty?
      end

      return if remaining.empty?

      # Fully expanded and still equal: number them.
      find_collisions(result.slice(*remaining)).each_value do |group|
        group[1..].each_with_index do |name, i|
          suffix = SUPERSCRIPTS[i] || (i + 2).to_s
          result[name] = "#{result[name]}#{suffix}"
        end
      end
    end

    # [{type:, length:, maxed:}, ...] for each token in the pattern.
    def parse_tokens(pattern)
      tokens = []
      pattern.scan(NameFormatter::TOKEN_RE) do |match|
        type = match[0]
        len = Regexp.last_match(0).length
        tokens << {type: type, length: len, maxed: len >= 4}
      end
      tokens
    end

    # The original pattern with its tokens resized, literals kept.
    def rebuild_pattern(tokens, original_pattern)
      ti = 0
      original_pattern.gsub(NameFormatter::TOKEN_RE) do
        tok = tokens[ti]
        ti += 1
        tok[:type] * tok[:length]
      end
    end

    private_class_method :merge_same_person, :find_collisions, :resolve_group,
      :parse_tokens, :rebuild_pattern
  end
end
