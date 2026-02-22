# frozen_string_literal: true

module Shine
  class MigrationParser
    # Methods that take a single table name as the first argument
    SINGLE_TABLE_METHODS = %w[
      create_table drop_table change_table
      add_column remove_column rename_column change_column
      add_index remove_index
      add_reference remove_reference
      add_belongs_to remove_belongs_to
      add_timestamps remove_timestamps
    ].freeze

    # Methods that take two table names as arguments
    DUAL_TABLE_METHODS = %w[
      add_foreign_key remove_foreign_key
    ].freeze

    SINGLE_TABLE_PATTERN = /\b(?:#{SINGLE_TABLE_METHODS.join("|")})\s+[:"](\w+)/
    DUAL_TABLE_PATTERN = /\b(?:#{DUAL_TABLE_METHODS.join("|")})\s+[:"](\w+)["\s,]+[:"](\w+)/

    def self.extract_tables(filepath)
      return [] if filepath.nil? || filepath.empty?
      return [] unless File.exist?(filepath)

      content = File.read(filepath)
      tables = []

      content.scan(SINGLE_TABLE_PATTERN) { |match| tables << match[0] }
      content.scan(DUAL_TABLE_PATTERN) { |match| tables.concat(match) }

      tables.uniq
    end
  end
end
