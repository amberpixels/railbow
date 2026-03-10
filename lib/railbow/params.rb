# frozen_string_literal: true

require "date"
require_relative "config"

module Railbow
  module Params
    module_function

    # Parse compound ENV value: "author:me,diff,base:develop"
    # → { "author" => "me", "diff" => true, "base" => "develop" }
    # Repeated keys collect into arrays: "hide:date,hide:author"
    # → { "hide" => ["date", "author"] }
    def parse_compound(value)
      return {} if value.nil? || value.strip.empty?

      result = {}
      value.strip.split(",").each do |token|
        token = token.strip
        next if token.empty?

        key, val = token.split(":", 2)
        key = key.strip
        val = val ? val.strip : true

        result[key] = if result.key?(key)
          Array(result[key]) << val
        else
          val
        end
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
      (ENV["RBW_SINCE"] || Config.load["since"] || "all").strip.downcase
    end

    def sort
      (ENV["RBW_SORT"] || Config.load["sort"] || "file").strip.downcase
    end

    # --- Compound: RBW_COMPACT ---

    def compact
      parse_compound(ENV["RBW_COMPACT"] || Config.load["compact"])
    end

    def compact_oneline?
      compact["oneline"] == true
    end

    def compact_strip_format?
      compact["strip-format"] == true
    end

    def compact_dense?
      compact["dense"] == true
    end

    def compact_noheader?
      compact["noheader"] == true
    end

    def compact_maxw
      val = compact["maxw"]
      val.is_a?(String) ? val.to_i : nil
    end

    def compact_hidden_columns
      val = compact["hide"]
      return [] if val.nil?
      Array(val)
    end

    def compact_options
      c = compact
      maxw_val = c["maxw"]
      hide_val = c["hide"]
      {
        oneline: c["oneline"] == true,
        dense: c["dense"] == true,
        noheader: c["noheader"] == true,
        maxw: maxw_val.is_a?(String) ? maxw_val.to_i : nil,
        hidden_columns: hide_val.nil? ? [] : Array(hide_val)
      }
    end

    def verb
      ENV["RBW_VERB"] || Config.load["verb"]
    end

    # --- Compound: RBW_GIT ---

    def git
      parse_compound(ENV["RBW_GIT"] || Config.load["git"])
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

    # Built-in regex for extracting ticket/task identifiers from branch names.
    # Matches patterns like: ws-123, 123, abc123, ab-123-456, feat/ws-1234, feat/123-some-feature
    TICKET_RE = /(?:^|\/)([a-z]{1,5}-?\d+(?:-\d+)*|\d+(?:-\d+)*)/i

    # Extract a ticket identifier from a branch name.
    # Returns the matched identifier or the original branch name if no match.
    def extract_branch_ticket(branch)
      m = branch.match(TICKET_RE)
      m ? m[1] : branch
    end

    # --- RBW_DATE ---

    def date_format
      val = ENV["RBW_DATE"] || Config.load["date"]
      return "full" if val.nil? || val.to_s.strip.empty?

      val.to_s.strip
    end

    # --- Compound: RBW_VIEW ---

    def view
      parse_compound(ENV["RBW_VIEW"] || Config.load["view"])
    end

    def view_calendar?
      view["calendar"] == true
    end

    def view_tables?
      val = view["tables"]
      if val == "nowrap"
        warn "  Warning: RBW_VIEW=tables:nowrap is deprecated. Use RBW_COMPACT=oneline instead."
      end
      !val.nil?
    end

    # --- Compound: RBW_CALENDAR ---

    def calendar
      parse_compound(ENV["RBW_CALENDAR"] || Config.load["calendar"])
    end

    def calendar_wticks?
      return false unless view_calendar?

      calendar["wticks"] == true
    end

    def calendar_label
      calendar["label"] || "%b %Y   W%V"
    end
  end
end
