# frozen_string_literal: true

require_relative "formatters/base"

module Railbow
  module RoutesFormatter
    VERB_COLORS = {
      "GET" => Formatters::Base::GREEN,
      "POST" => Formatters::Base::YELLOW,
      "PATCH" => Formatters::Base::CYAN,
      "PUT" => Formatters::Base::CYAN,
      "DELETE" => Formatters::Base::RED
    }.freeze

    RESET = Formatters::Base::RESET
    BOLD = Formatters::Base::BOLD
    DIM = Formatters::Base::DIM
    CYAN = Formatters::Base::CYAN

    HELP_TEXT_PLAIN = <<~HELP

      Railbow Routes Options:

        GROUP=controller  Group routes by controller (default)
        GROUP=verb        Group routes by HTTP verb
        GROUP=none        Flat list, no grouping
        COMPACT=0         Keep (.:format) suffixes
        HELP=1            Show this help message

      Example: GROUP=none rails routes

    HELP

    HELP_TEXT_COLOR = <<~HELP

      #{BOLD}Railbow Routes Options:#{RESET}

        #{CYAN}GROUP=controller#{RESET}  Group routes by controller (default)
        #{CYAN}GROUP=verb#{RESET}        Group routes by HTTP verb
        #{CYAN}GROUP=none#{RESET}        Flat list, no grouping
        #{CYAN}COMPACT=0#{RESET}         Keep (.:format) suffixes
        #{CYAN}HELP=1#{RESET}            Show this help message

      #{DIM}Example: GROUP=none rails routes#{RESET}

    HELP

    HEADER_LABELS = ["Verb", "URI Pattern", "Controller#Action", "Prefix"].freeze
    FORMAT_SUFFIX = "(.:format)"

    def section_title(title)
      if tty?
        @buffer << "\n#{BOLD}#{CYAN}#{title}:#{RESET}"
      else
        super
      end
    end

    def header(_routes)
      super unless tty?
    end

    def section(routes)
      if ENV["HELP"] == "1"
        @buffer << (tty? ? HELP_TEXT_COLOR : HELP_TEXT_PLAIN)
        return
      end

      unless tty?
        super
        return
      end

      group_by = (ENV["GROUP"] || "controller").downcase
      compact = compact_mode?
      prepared = routes.map { |r| prepare_route(r, compact) }

      if group_by == "none"
        render_group(nil, prepared)
      else
        groups = group_routes(prepared, group_by)
        groups.each { |label, group| render_group(label, group) }
      end
    end

    private

    def group_routes(routes, group_by)
      case group_by
      when "controller"
        grouped = routes.group_by { |r| r[:reqs].include?("#") ? r[:reqs].split("#").first : "(other)" }
        other = grouped.delete("(other)")
        grouped["(other)"] = other if other
        grouped
      when "verb"
        routes.group_by { |r| r[:verb].empty? ? "(none)" : r[:verb] }
      else
        {"All" => routes}
      end
    end

    def render_group(label, routes)
      if label
        @buffer << ""
        @buffer << "#{BOLD}#{CYAN}\u2500\u2500 #{label} \u2500\u2500#{RESET}"
      end

      verb_w, path_w, reqs_w = compute_widths(routes)

      @buffer << render_header(verb_w, path_w, reqs_w)
      routes.each do |r|
        @buffer << render_route(r, verb_w, path_w, reqs_w)
      end
    end

    def compute_widths(routes)
      verb_label, path_label, reqs_label, = HEADER_LABELS

      verb_w = [routes.map { |r| r[:verb].length }.max || 0, verb_label.length].max
      path_w = [routes.map { |r| r[:path].length }.max || 0, path_label.length].max
      reqs_w = [routes.map { |r| r[:reqs].length }.max || 0, reqs_label.length].max

      [verb_w, path_w, reqs_w]
    end

    def render_header(verb_w, path_w, reqs_w)
      verb_label, path_label, reqs_label, prefix_label = HEADER_LABELS
      verb_h = "#{BOLD}#{verb_label}#{RESET}" + (" " * (verb_w - verb_label.length))
      path_h = "#{BOLD}#{path_label}#{RESET}" + (" " * (path_w - path_label.length))
      reqs_h = "#{BOLD}#{reqs_label}#{RESET}" + (" " * (reqs_w - reqs_label.length))

      "#{verb_h} #{path_h} #{reqs_h} #{BOLD}#{prefix_label}#{RESET}"
    end

    def render_route(r, verb_w, path_w, reqs_w)
      verb_col = pad_left(colorize_verb(r[:verb]), r[:verb], verb_w)
      path_col = pad_left(colorize_path(r[:path]), r[:path], path_w)
      reqs_col = pad_left(colorize_reqs(r[:reqs]), r[:reqs], reqs_w)
      name_col = r[:name].empty? ? "" : " #{colorize_name(r[:name])}"

      "#{verb_col} #{path_col} #{reqs_col}#{name_col}"
    end

    def prepare_route(route, compact)
      r = route.dup
      r[:path] = r[:path].sub("(.:format)", "") if compact
      r
    end

    def compact_mode?
      ENV["COMPACT"] != "0"
    end

    def colorize_verb(verb)
      return verb if verb.empty?

      verb.split("|").map { |v|
        color = VERB_COLORS[v]
        color ? "#{color}#{v}#{RESET}" : v
      }.join("#{DIM}|#{RESET}")
    end

    def colorize_path(path)
      return path if path.empty?

      path.gsub(/:[a-z_]+|\*[a-z_]+/) { |match| "#{CYAN}#{match}#{RESET}" }
    end

    def colorize_reqs(reqs)
      return reqs if reqs.empty?

      if reqs.include?("#")
        controller, action = reqs.split("#", 2)
        "#{BOLD}#{controller}#{RESET}#{DIM}##{RESET}#{action}"
      else
        "#{DIM}#{reqs}#{RESET}"
      end
    end

    def colorize_name(name)
      return name if name.empty?

      "#{DIM}#{name}#{RESET}"
    end

    def pad_left(colored, plain, width)
      padding = width - measure_width(plain)
      (padding > 0) ? "#{colored}#{" " * padding}" : colored
    end

    def measure_width(str)
      Unicode::DisplayWidth.of(str)
    end

    def tty?
      $stdout.tty?
    end
  end
end
