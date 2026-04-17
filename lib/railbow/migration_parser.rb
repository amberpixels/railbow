# frozen_string_literal: true

require "active_support/inflector"

module Railbow
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

    # SQL keywords followed by a table name
    SQL_TABLE_PATTERNS = [
      /\bUPDATE\s+["']?(\w+)["']?/i,
      /\bINSERT\s+INTO\s+["']?(\w+)["']?/i,
      /\bDELETE\s+FROM\s+["']?(\w+)["']?/i,
      /\bALTER\s+TABLE\s+["']?(\w+)["']?/i,
      /\bTRUNCATE\s+(?:TABLE\s+)?["']?(\w+)["']?/i,
      /\bDROP\s+TABLE\s+(?:IF\s+EXISTS\s+)?["']?(\w+)["']?/i,
      /\bCREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?["']?(\w+)["']?/i
    ].freeze

    # AR class-level query/mutation methods that strongly signal a constant is a model.
    # Kept narrow on purpose — methods like `find`, `all`, `first`, `count`, `create`,
    # `new`, `transaction`, `order`, `includes` collide with stdlib/non-model constants
    # (e.g. Time.new, File.find, Array#first) and would produce false positives.
    MODEL_AR_METHODS = %w[
      find_each find_in_batches
      find_by find_by!
      find_or_create_by find_or_create_by!
      find_or_initialize_by
      where update_all delete_all destroy_all
      upsert_all insert_all
      pluck pick
      in_batches
    ].freeze

    MODEL_REFERENCE_PATTERN = /\b([A-Z][A-Za-z0-9]*(?:::[A-Z][A-Za-z0-9]*)*)\.(?:#{MODEL_AR_METHODS.join("|")})\b/

    def self.extract_tables(filepath)
      return [] if filepath.nil? || filepath.empty?
      return [] unless File.exist?(filepath)

      extract_tables_from_content(File.read(filepath))
    end

    def self.extract_tables_from_content(content)
      return [] if content.nil? || content.empty?

      tables = []

      content.scan(SINGLE_TABLE_PATTERN) { |match| tables << match[0] }
      content.scan(DUAL_TABLE_PATTERN) { |match| tables.concat(match) }
      SQL_TABLE_PATTERNS.each do |pattern|
        content.scan(pattern) { |match| tables << match[0] }
      end
      tables.uniq!

      # Model-based detection is heuristic (a constant that happens to respond
      # to one of these methods isn't necessarily an AR model). Only use it to
      # supplement sparse DDL/SQL findings — skip once we already know of ≥2
      # tables, and cap the final total at 2.
      if tables.size < 2
        content.scan(MODEL_REFERENCE_PATTERN) do |match|
          break if tables.size >= 2
          table = ActiveSupport::Inflector.tableize(match[0].split("::").last)
          tables << table unless tables.include?(table)
        end
      end

      tables
    end
  end
end
