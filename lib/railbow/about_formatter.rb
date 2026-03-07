# frozen_string_literal: true

require_relative "formatters/base"
require_relative "config"
require_relative "table"

module Railbow
  module AboutFormatter
    def to_s
      return super if Railbow.plain?

      formatter = Formatters::Base.new

      columns = [
        Table::Column.new(label: "Property", sticky: true),
        Table::Column.new(label: "Value")
      ]

      rows = @@properties.map do |(name, value)|
        val = value.respond_to?(:call) ? value.call : value
        [formatter.bold(name), val.to_s]
      end

      renderer = Table::Renderer.new(
        columns: columns,
        theme: Table::Themes::PLAIN,
        compact: Railbow::Params.compact_options,
        aliases: Railbow::Config.table_aliases
      )

      output = +"\n"
      output << renderer.render(rows)
      output << "\n"
      output
    end
  end
end
