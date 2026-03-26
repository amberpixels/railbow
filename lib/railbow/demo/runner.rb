# frozen_string_literal: true

require_relative "../../railbow"
require_relative "../logo"

module Railbow
  module Demo
    class Runner
      SUBCOMMANDS = %w[status migrate routes all].freeze

      def self.run(subcommand = "status")
        subcommand = subcommand.to_s.downcase
        unless SUBCOMMANDS.include?(subcommand)
          warn "Unknown demo: #{subcommand}"
          warn "Available: #{SUBCOMMANDS.join(", ")}"
          exit 1
        end

        Railbow.print_logo
        puts

        if subcommand == "all"
          run_all
        else
          run_one(subcommand)
        end
      end

      def self.run_one(subcommand)
        case subcommand
        when "status"
          require_relative "status_demo"
          StatusDemo.run
        when "migrate"
          require_relative "migrate_demo"
          MigrateDemo.run
        when "routes"
          require_relative "routes_demo"
          RoutesDemo.run
        end
      end

      def self.run_all
        %w[status migrate routes].each do |sub|
          puts "\n\e[1m\e[36m── railbow demo #{sub} ──\e[0m\n"
          run_one(sub)
        end
      end
    end
  end
end
