# frozen_string_literal: true

require_relative "formatters/base"
require_relative "config"
require_relative "table"

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

    HELP_TEXT_COLOR = <<~HELP

      #{BOLD}Railbow Routes Options:#{RESET}

        #{CYAN}RBW_VERB=GET#{RESET}          Show only GET routes
        #{CYAN}RBW_VERB=POST,PUT#{RESET}     Show only POST and PUT routes
        #{CYAN}RBW_COMPACT=strip-format#{RESET}  Strip (.:format) suffixes
        #{CYAN}RBW_COMPACT=oneline#{RESET}   Truncate instead of wrapping
        #{CYAN}RBW_COMPACT=dense#{RESET}     Remove cell padding
        #{CYAN}RBW_COMPACT=noheader#{RESET}  Hide table header row
        #{CYAN}RBW_COMPACT=maxw:40#{RESET}   Cap column widths
        #{CYAN}RBW_COMPACT=hide:prefix#{RESET}  Hide a column by name
        #{CYAN}RBW_PLAIN=1#{RESET}           Disable Railbow formatting (plain Rails output)
        #{CYAN}RBW_HELP=1#{RESET}            Show this help message

      #{DIM}Combine: RBW_COMPACT=strip-format,dense,noheader#{RESET}
      #{DIM}Auto-disabled when piped, in CI, or when called by an LLM agent.#{RESET}
      #{DIM}Example: RBW_VERB=GET rails routes#{RESET}

    HELP

    def section_title(title)
      return super unless tty?
      return if Railbow::Params.help?

      @buffer << "\n#{BOLD}#{CYAN}#{title}:#{RESET}"
    end

    def header(routes)
      super unless tty?
    end

    def section(routes)
      return super unless tty?

      if Railbow::Params.help?
        unless @help_shown
          @buffer << HELP_TEXT_COLOR
          @help_shown = true
        end
        return
      end

      strip_format = Railbow::Params.compact_strip_format?
      prepared = routes.map { |r| prepare_route(r, strip_format) }
      prepared = filter_by_verb(prepared)

      groups = group_routes(prepared)
      groups.each { |label, group| render_group(label, group) }
    end

    private

    def group_routes(routes)
      grouped = routes.group_by { |r| r[:reqs].include?("#") ? r[:reqs].split("#").first : "(other)" }
      other = grouped.delete("(other)")
      grouped["(other)"] = other if other
      grouped
    end

    def filter_by_verb(routes)
      verb_filter = Railbow::Params.verb
      return routes if verb_filter.nil? || verb_filter.strip.empty? || verb_filter.strip.upcase == "ALL"

      allowed = verb_filter.split(",").map { |v| v.strip.upcase }
      routes.select { |r| (r[:verb].split("|") & allowed).any? }
    end

    def render_group(label, routes)
      if label
        @buffer << ""
        @buffer << "#{BOLD}#{CYAN}\u2500\u2500 #{label} \u2500\u2500#{RESET}"
      end

      columns = [
        Table::Column.new(label: "Verb", sticky: true),
        Table::Column.new(label: "URI Pattern", sticky: true),
        Table::Column.new(label: "Controller#Action"),
        Table::Column.new(label: "Prefix")
      ]

      rows = routes.map { |r|
        [
          colorize_verb(r[:verb]),
          colorize_path(r[:path]),
          colorize_reqs(r[:reqs]),
          r[:name].empty? ? "" : colorize_name(r[:name])
        ]
      }

      renderer = Table::Renderer.new(
        columns: columns,
        theme: Table::Themes::PLAIN,
        compact: Railbow::Params.compact_options,
        aliases: Railbow::Config.table_aliases
      )
      @buffer << renderer.render(rows)
    end

    def prepare_route(route, compact)
      r = route.dup
      r[:path] = r[:path].sub("(.:format)", "") if compact
      r
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

    def tty?
      !Railbow.plain?
    end
  end
end
