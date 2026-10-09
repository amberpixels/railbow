# frozen_string_literal: true

require "benchmark"
require_relative "formatters/base"

module Railbow
  module MigrationFormatter
    FORMATTER = Formatters::Base.new.freeze

    def announce(message)
      return super if Railbow.plain?

      Railbow.guard(-> { super }) { railbow_announce(message) }
    end

    # The yield runs the migration itself, so it stays outside the guard: a
    # failing migration must raise as usual, and a formatting error must not
    # re-run it through super. The fallback prints what Rails would have.
    def say_with_time(message)
      return super { yield } if Railbow.plain?

      f = FORMATTER
      result = nil
      time = Benchmark.measure { result = yield }

      plain = lambda do
        say(message)
        say("%.4fs" % time.real, :subitem)
        say("#{result} rows", :subitem) if result.is_a?(Integer)
      end
      Railbow.guard(plain) do
        timing = f.format_timing(time.real)
        write "  #{f.green(f.emoji(:check))} #{message} → #{timing}"
        say("#{result} rows", :subitem) if result.is_a?(Integer)
      end

      result
    end

    def say(message, subitem = false)
      return super if Railbow.plain?

      prefix = subitem ? "     " : "  "
      write("#{prefix}#{message}")
    end

    def write(text = "")
      return super if Railbow.plain?

      puts text
    end

    private

    def railbow_announce(message)
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
  end
end
