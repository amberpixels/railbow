# frozen_string_literal: true

require_relative "../formatters/base"
require_relative "fixtures"

module Railbow
  module Demo
    class MigrateDemo
      def self.run
        new.run
      end

      def run
        f = Railbow::Formatters::Base.new

        Fixtures::MIGRATE_STEPS.each do |name, steps|
          puts
          puts f.cyan("#{f.emoji(:migrating)} #{name}: migrating...")

          total_time = 0.0
          steps.each do |operation, seconds|
            total_time += seconds
            timing = f.format_timing(seconds)
            puts "  #{f.green(f.emoji(:check))} #{operation} \u2192 #{timing}"
          end

          total_timing = f.format_timing(total_time)
          puts f.green("#{f.emoji(:migrated)} #{name}: migrated") + " (#{total_timing} total)"
        end

        puts
      end
    end
  end
end
