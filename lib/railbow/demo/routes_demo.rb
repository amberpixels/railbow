# frozen_string_literal: true

require_relative "../formatters/base"
require_relative "../table"
require_relative "../config"
require_relative "fixtures"

module Railbow
  module Demo
    class RoutesDemo
      VERB_COLORS = {
        "GET" => Railbow::Formatters::Base::GREEN,
        "POST" => Railbow::Formatters::Base::YELLOW,
        "PATCH" => Railbow::Formatters::Base::CYAN,
        "PUT" => Railbow::Formatters::Base::CYAN,
        "DELETE" => Railbow::Formatters::Base::RED
      }.freeze

      RESET = Railbow::Formatters::Base::RESET
      BOLD = Railbow::Formatters::Base::BOLD
      DIM = Railbow::Formatters::Base::DIM
      CYAN = Railbow::Formatters::Base::CYAN

      def self.run
        new.run
      end

      def run
        routes = Fixtures::ROUTES
        groups = routes.group_by { |r| r[:reqs].include?("#") ? r[:reqs].split("#").first : "(other)" }

        lines = []
        groups.each do |label, group_routes|
          lines << ""
          lines << "#{BOLD}#{CYAN}\u2500\u2500 #{label} \u2500\u2500#{RESET}"

          columns = [
            Railbow::Table::Column.new(label: "Verb", sticky: true),
            Railbow::Table::Column.new(label: "URI Pattern", sticky: true),
            Railbow::Table::Column.new(label: "Controller#Action"),
            Railbow::Table::Column.new(label: "Prefix")
          ]

          rows = group_routes.map { |r|
            [
              colorize_verb(r[:verb]),
              colorize_path(r[:path]),
              colorize_reqs(r[:reqs]),
              r[:name].empty? ? "" : "#{DIM}#{r[:name]}#{RESET}"
            ]
          }

          renderer = Railbow::Table::Renderer.new(
            columns: columns,
            theme: Railbow::Table::Themes::PLAIN,
            compact: {oneline: false, dense: false, noheader: false, maxw: nil, hidden_columns: []},
            aliases: Railbow::Config.table_aliases
          )
          lines << renderer.render(rows)
        end

        puts lines.join("\n")
      end

      private

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
    end
  end
end
