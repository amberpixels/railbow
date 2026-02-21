# frozen_string_literal: true

require_relative "formatters/base"

module Shine
  module MigrationFormatter
    FORMATTER = Formatters::Base.new.freeze

    def announce(message)
      f = FORMATTER
      migration_name = self.class.name&.demodulize || "Migration"

      line = case message
      when /migrating/i
        f.cyan("#{f.emoji(:migrating)} #{migration_name}: migrating...")
      when /migrated\s*\((\d+\.\d+)s\)/i
        raw_seconds = Regexp.last_match(1).to_f
        formatted = f.format_timing(raw_seconds)
        f.green("#{f.emoji(:migrated)} #{migration_name}: migrated") + " (#{formatted} total)"
      when /reverting/i
        f.yellow("#{f.emoji(:reverting)} #{migration_name}: reverting...")
      when /reverted\s*\((\d+\.\d+)s\)/i
        raw_seconds = Regexp.last_match(1).to_f
        formatted = f.format_timing(raw_seconds)
        f.green("#{f.emoji(:reverted)} #{migration_name}: reverted") + " (#{formatted} total)"
      else
        "#{migration_name}: #{message}"
      end

      write ""
      write line
    end

    def say_with_time(message)
      f = FORMATTER
      result = nil
      time = Benchmark.measure { result = yield }

      timing = f.format_timing(time.real)
      write "  #{f.green(f.emoji(:check))} #{message} → #{timing}"
      say("#{result} rows", :subitem) if result.is_a?(Integer)

      result
    end

    def say(message, subitem = false)
      prefix = subitem ? "     " : "  "
      write("#{prefix}#{message}")
    end

    def write(text = "")
      puts text
    end
  end
end
