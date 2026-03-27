# frozen_string_literal: true

require_relative "name_formatter"

module Railbow
  # Detects and resolves collisions when multiple different names produce the
  # same formatted output.  Works by progressively expanding pattern tokens
  # (F → FF → FFF → FFFF, then L) until every distinct raw name maps to a
  # unique formatted string.
  #
  # Names that share the same first+last name but differ only in middle name
  # are treated as the same person and merged before collision detection.
  #
  #   NameCollisionResolver.resolve(["John Doe", "Jane Doe"], "F L")
  #   # => {"John Doe" => "Jo D", "Jane Doe" => "Ja D"}
  module NameCollisionResolver
    SUPERSCRIPTS = %w[² ³ ⁴ ⁵ ⁶ ⁷ ⁸ ⁹].freeze

    module_function

    # @param names [Array<String, nil>] raw author names (may contain duplicates/nils)
    # @param pattern [String] a NameFormatter pattern or preset name
    # @return [Hash{String => String}] raw_name → disambiguated formatted name
    def resolve(names, pattern)
      pattern = NameFormatter::PRESETS.fetch(pattern, pattern)
      uniq_names = names.compact.reject(&:empty?).uniq

      # Merge names that are the same person (same first+last, differ only in middle)
      canonical, aliases = merge_same_person(uniq_names)

      # Format every canonical name with the base pattern
      result = {}
      canonical.each { |n| result[n] = NameFormatter.format(n, pattern) }

      # Find collision groups (different raw names → same formatted output)
      collisions = find_collisions(result)
      unless collisions.empty?
        tokens = parse_tokens(pattern)
        collisions.each do |_formatted, raw_names|
          resolve_group(raw_names, pattern, tokens, result)
        end
      end

      # Expand aliases: all variant spellings get the same formatted output
      aliases.each { |variant, canon| result[variant] = result[canon] }

      result
    end

    # --- private helpers ---

    # Group names by (first, last) and pick the shortest as canonical.
    # Returns [canonical_names, aliases_hash] where aliases maps variant → canonical.
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
        # Pick shortest name as canonical (the one without middle name)
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

    # Resolve a single collision group by progressively expanding tokens.
    # Only names that still collide continue to be expanded; once a name
    # becomes unique it keeps its current (minimal) expansion.
    def resolve_group(raw_names, base_pattern, base_tokens, result)
      remaining = raw_names.dup
      tokens = base_tokens.map(&:dup)

      # Expansion order: exhaust all F tokens first, then L tokens
      expansion_order = tokens.each_index.sort_by { |i| (tokens[i][:type] == "F") ? 0 : 1 }

      expansion_order.each do |ti|
        tok = tokens[ti]
        next if tok[:maxed]

        until tok[:maxed]
          tok[:length] += 1
          tok[:maxed] = true if tok[:length] >= 4
          current_pattern = rebuild_pattern(tokens, base_pattern)

          remaining.each { |n| result[n] = NameFormatter.format(n, current_pattern) }

          # Check collisions only within this group (not the full result),
          # so expansion from one group can't chase collisions with other groups
          still_colliding = find_collisions(result.slice(*raw_names))
          if still_colliding.empty?
            remaining = []
            break
          end

          # Only keep expanding names that still collide within the group
          remaining = still_colliding.values.flatten
        end

        break if remaining.empty?
      end

      return if remaining.empty?

      # Last resort: numeric suffixes
      find_collisions(result.slice(*remaining)).each_value do |group|
        group[1..].each_with_index do |name, i|
          suffix = SUPERSCRIPTS[i] || (i + 2).to_s
          result[name] = "#{result[name]}#{suffix}"
        end
      end
    end

    # Parse pattern into token descriptors: [{type:, length:, maxed:}, ...]
    def parse_tokens(pattern)
      tokens = []
      pattern.scan(NameFormatter::TOKEN_RE) do |match|
        type = match[0]
        len = Regexp.last_match(0).length
        tokens << {type: type, length: len, maxed: len >= 4}
      end
      tokens
    end

    # Rebuild a pattern string from token descriptors, preserving literals.
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
