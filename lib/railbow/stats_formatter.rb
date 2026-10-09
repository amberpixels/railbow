# frozen_string_literal: true

require_relative "formatters/base"
require_relative "config"
require_relative "table"

module Railbow
  module StatsFormatter
    RESET = Formatters::Base::RESET
    DIM = Formatters::Base::DIM
    CODE_COLOR = "\e[38;5;76m"  # green
    TEST_COLOR = "\e[38;5;39m"  # cyan

    BAR_WIDTH = 16
    BAR_EIGHTHS = ["", "▏", "▎", "▍", "▌", "▋", "▊", "▉"].freeze
    FULL_BLOCK = "█"

    # Rails 8 names the class Rails::CodeStatistics, Rails 7.2 a top-level
    # CodeStatistics; both live in "rails/code_statistics". Prepending twice is
    # a no-op, so every entry point may call this.
    def self.install!
      require "rails/code_statistics"
      klass = defined?(Rails::CodeStatistics) ? Rails::CodeStatistics : ::CodeStatistics
      klass.prepend(self)
    rescue LoadError
      # railties without code statistics: nothing to decorate
    end

    # Stock Rails prints the table from to_s and returns nil, and both the
    # stats command and the rake task rely on that, so this prints too.
    def to_s
      return super if Railbow.plain?

      Railbow.guard(-> { super }) do
        puts railbow_render
        nil
      end
    end

    private

    def railbow_render
      f = Formatters::Base.new
      tests = railbow_test_types
      names = @pairs.map(&:first)
      code_names = names.reject { |n| tests.include?(n) }
      test_names = names.select { |n| tests.include?(n) }

      total = railbow_sum(@statistics.values)
      max_loc = @statistics.values.map(&:code_lines).max.to_i

      rows = []
      separators = {}
      [["Code", code_names, CODE_COLOR, false], ["Tests", test_names, TEST_COLOR, true]].each do |label, group, color, test|
        next if group.empty?

        # A heading row rather than a renderer separator, which would put the
        # label past the first column.
        rows << [Table::Themes::WALLS.format_separator.call(label), *Array.new(7, "")]
        group.each do |name|
          rows << railbow_row(f, name, @statistics[name], total, max_loc, color, test: test)
        end
      end
      separators[rows.size] = "" if rows.size > 1
      rows << railbow_total_row(f, total)

      renderer = Table::Renderer.new(
        columns: railbow_columns,
        theme: Table::Themes::WALLS,
        compact: Railbow::Params.compact_options,
        aliases: Railbow::Config.table_aliases
      )

      out = +"\n"
      out << renderer.render(rows, separators: separators)
      out << "\n\n"
      out << railbow_summary(f, code_names, test_names)
      out << "\n"
      out
    end

    def railbow_columns
      [
        Table::Column.new(label: "Name", sticky: true),
        Table::Column.new(label: "Lines", align: :right),
        Table::Column.new(label: "LOC", align: :right),
        Table::Column.new(label: "Classes", align: :right),
        Table::Column.new(label: "Methods", align: :right),
        Table::Column.new(label: "M/C", align: :right),
        Table::Column.new(label: "LOC/M", align: :right),
        Table::Column.new(label: "Share of LOC")
      ]
    end

    # M/C and LOC/M say little about test code, where most blocks are not
    # methods, so on test rows they step back.
    def railbow_row(f, name, stats, total, max_loc, color, test:)
      ratios = railbow_ratios(stats).map { |v| test ? f.dim(railbow_num(v)) : railbow_count(f, v) }
      [
        name,
        railbow_count(f, stats.lines),
        railbow_count(f, stats.code_lines),
        railbow_count(f, stats.classes),
        railbow_count(f, stats.methods),
        *ratios,
        railbow_share(f, stats.code_lines, total.code_lines, max_loc, color)
      ]
    end

    def railbow_total_row(f, total)
      cells = [total.lines, total.code_lines, total.classes, total.methods, *railbow_ratios(total)]
      [f.bold("Total"), *cells.map { |v| f.bold(railbow_num(v)) }, ""]
    end

    # Integer math, as stock Rails does it, so the numbers match its table.
    def railbow_ratios(stats)
      m_over_c = stats.classes.zero? ? 0 : stats.methods / stats.classes
      loc_over_m = stats.methods.zero? ? 0 : (stats.code_lines / stats.methods) - 2
      [m_over_c, loc_over_m]
    end

    # The bar is scaled to the biggest row so small directories stay visible;
    # the percentage is of the whole codebase.
    def railbow_share(f, loc, total_loc, max_loc, color)
      return f.dim("-") if loc.zero? || total_loc.zero?

      eighths = (BAR_WIDTH * 8 * loc.fdiv(max_loc)).round.clamp(1, BAR_WIDTH * 8)
      bar = (FULL_BLOCK * (eighths / 8)) + BAR_EIGHTHS[eighths % 8]
      share = 100.0 * loc / total_loc
      pct = (share < 0.1) ? "<0.1%" : format("%.1f%%", share)
      "#{color}#{bar.ljust(BAR_WIDTH)}#{RESET} #{f.dim(pct.rjust(5))}"
    end

    def railbow_summary(f, code_names, test_names)
      code = code_names.sum { |n| @statistics[n].code_lines }
      test = test_names.sum { |n| @statistics[n].code_lines }

      parts = ["#{CODE_COLOR}Code#{RESET} #{f.bold(railbow_num(code))} LOC"]
      parts << "#{TEST_COLOR}Tests#{RESET} #{f.bold(railbow_num(test))} LOC"
      parts << "Code to Test Ratio #{f.bold(format("1:%.1f", test.fdiv(code)))}" if code.positive?
      "  #{parts.join(f.dim("   ·   "))}\n"
    end

    def railbow_sum(calculators)
      total = Struct.new(:lines, :code_lines, :classes, :methods).new(0, 0, 0, 0)
      calculators.each do |s|
        total.lines += s.lines
        total.code_lines += s.code_lines
        total.classes += s.classes
        total.methods += s.methods
      end
      total
    end

    # Rails 8 keeps the list in a class attribute that register_directory
    # extends; Rails 7.2 in a constant that rspec-rails appends to.
    def railbow_test_types
      respond_to?(:test_types, true) ? test_types : self.class::TEST_TYPES
    end

    def railbow_count(f, value)
      value.zero? ? f.dim("0") : railbow_num(value)
    end

    def railbow_num(value)
      value.to_s.reverse.scan(/\d{1,3}/).join(",").reverse.then { |s| value.negative? ? "-#{s}" : s }
    end
  end
end
