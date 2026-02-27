# frozen_string_literal: true

require "date"

module Railbow
  module Params
    module_function

    # Parse compound ENV value: "author:me,diff,base:develop"
    # → { "author" => "me", "diff" => true, "base" => "develop" }
    def parse_compound(value)
      return {} if value.nil? || value.strip.empty?

      result = {}
      value.strip.split(",").each do |token|
        token = token.strip
        next if token.empty?

        key, val = token.split(":", 2)
        result[key.strip] = val ? val.strip : true
      end
      result
    end

    def truthy?(value)
      %w[1 true yes on].include?(value.to_s.strip.downcase)
    end

    # Parse SINCE value like "2mo", "30d", "1w", "1y" into a Date cutoff.
    # Returns nil for "all" or unrecognized values.
    def parse_since(value, context: nil)
      return nil if value.nil? || value.strip.downcase == "all"

      match = value.strip.match(/^(\d+)(d|w|mo|m|y)$/i)
      unless match
        label = context ? " for #{context}" : ""
        warn "  Warning: unrecognized RBW_SINCE=#{value}#{label}, showing all"
        return nil
      end

      amount = match[1].to_i
      unit = match[2].downcase

      case unit
      when "d" then Date.today - amount
      when "w" then Date.today - (amount * 7)
      when "mo", "m" then Date.today.prev_month(amount)
      when "y" then Date.today.prev_year(amount)
      end
    end

    # --- Global accessors ---

    def help?
      truthy?(ENV["RBW_HELP"])
    end

    def plain?
      truthy?(ENV["RBW_PLAIN"])
    end

    def since
      ENV.fetch("RBW_SINCE", "all").strip.downcase
    end

    def sort
      ENV.fetch("RBW_SORT", "file").strip.downcase
    end

    def compact
      ENV.fetch("RBW_COMPACT", nil)
    end

    def verb
      ENV.fetch("RBW_VERB", nil)
    end

    # --- Compound: RBW_GIT ---

    def git
      parse_compound(ENV["RBW_GIT"])
    end

    def git_author
      val = git["author"]
      return "off" if val.nil?
      (val == true) ? "all" : val.strip.downcase
    end

    def git_diff?
      git["diff"] == true
    end

    def git_base
      val = git["base"]
      val.is_a?(String) ? val : ""
    end

    def git_mask
      val = git["mask"]
      val.is_a?(String) ? val : ""
    end

    # --- RBW_DATE ---

    def date_format
      val = ENV["RBW_DATE"]
      return "full" if val.nil? || val.strip.empty?

      val.strip
    end

    # --- Compound: RBW_VIEW ---

    def view
      parse_compound(ENV["RBW_VIEW"])
    end

    def view_calendar?
      view["calendar"] == true
    end

    def view_tables?
      !view["tables"].nil?
    end

    def view_tables_nowrap?
      view["tables"] == "nowrap" || view["nowrap"] == true
    end

    # --- Compound: RBW_CALENDAR ---

    def calendar
      parse_compound(ENV["RBW_CALENDAR"])
    end

    def calendar_wticks?
      return false unless view_calendar?

      calendar["wticks"] == true
    end
  end
end
