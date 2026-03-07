# frozen_string_literal: true

require_relative "formatters/base"
require_relative "config"
require_relative "table"

module Railbow
  module StatsFormatter
    def to_s
      return super if Railbow.plain?

      formatter = Formatters::Base.new

      columns = [
        Table::Column.new(label: "Name", sticky: true),
        Table::Column.new(label: "Lines", align: :right),
        Table::Column.new(label: "LOC", align: :right),
        Table::Column.new(label: "Classes", align: :right),
        Table::Column.new(label: "Methods", align: :right),
        Table::Column.new(label: "M/C", align: :right),
        Table::Column.new(label: "LOC/M", align: :right)
      ]

      rows = []
      total_lines = 0
      total_loc = 0
      total_classes = 0
      total_methods = 0
      code_loc = 0
      test_loc = 0

      @pairs.each do |pair|
        name, stats = pair
        lines = stats.lines
        loc = stats.code_lines
        classes = stats.classes
        methods = stats.methods
        mc = (classes > 0) ? (methods.to_f / classes).round(0).to_i : 0
        locm = (methods > 0) ? ((loc.to_f / methods) - 2).round(0).to_i : 0

        total_lines += lines
        total_loc += loc
        total_classes += classes
        total_methods += methods

        if stats.test_file?
          test_loc += loc
        else
          code_loc += loc
        end

        rows << [
          name,
          lines.to_s,
          loc.to_s,
          classes.to_s,
          methods.to_s,
          mc.to_s,
          locm.to_s
        ]
      end

      # Total row
      total_mc = (total_classes > 0) ? (total_methods.to_f / total_classes).round(0).to_i : 0
      total_locm = (total_methods > 0) ? ((total_loc.to_f / total_methods) - 2).round(0).to_i : 0

      rows << [
        formatter.bold("Total"),
        formatter.bold(total_lines.to_s),
        formatter.bold(total_loc.to_s),
        formatter.bold(total_classes.to_s),
        formatter.bold(total_methods.to_s),
        formatter.bold(total_mc.to_s),
        formatter.bold(total_locm.to_s)
      ]

      renderer = Table::Renderer.new(
        columns: columns,
        theme: Table::Themes::WALLS,
        compact: Railbow::Params.compact_options,
        aliases: Railbow::Config.table_aliases
      )

      output = +"\n"
      output << renderer.render(rows)
      output << "\n"

      # Code/test ratio
      if code_loc > 0 && test_loc > 0
        ratio = (test_loc.to_f / code_loc).round(1)
        output << "\n  #{formatter.bold("Code LOC:")} #{code_loc}   " \
                  "#{formatter.bold("Test LOC:")} #{test_loc}   " \
                  "#{formatter.bold("Code to Test Ratio:")} 1:#{ratio}\n"
      end

      output
    end
  end
end
