# frozen_string_literal: true

require "active_support/inflector"

module Railbow
  class MigrationParser
    SINGLE_TABLE_METHODS = %w[
      create_table drop_table change_table
      add_column remove_column rename_column change_column
      change_column_default change_column_null
      add_index remove_index
      add_reference remove_reference
      add_belongs_to remove_belongs_to
      add_timestamps remove_timestamps
    ].freeze

    DUAL_TABLE_METHODS = %w[
      add_foreign_key remove_foreign_key
    ].freeze

    # Dual-table methods are included here too: their first argument is always a
    # table, even when the second is passed as `to_table:` instead of positionally.
    SINGLE_TABLE_PATTERN = /\b(?:#{(SINGLE_TABLE_METHODS + DUAL_TABLE_METHODS).join("|")})\s+[:"](\w+)/
    DUAL_TABLE_PATTERN = /\b(?:#{DUAL_TABLE_METHODS.join("|")})\s+[:"](\w+)["\s,]+[:"](\w+)/

    SQL_TABLE_PATTERNS = [
      /\bUPDATE\s+["']?(\w+)["']?/i,
      /\bINSERT\s+INTO\s+["']?(\w+)["']?/i,
      /\bDELETE\s+FROM\s+["']?(\w+)["']?/i,
      /\bALTER\s+TABLE\s+["']?(\w+)["']?/i,
      /\bTRUNCATE\s+(?:TABLE\s+)?["']?(\w+)["']?/i,
      /\bDROP\s+TABLE\s+(?:IF\s+EXISTS\s+)?["']?(\w+)["']?/i,
      /\bCREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?["']?(\w+)["']?/i
    ].freeze

    # A table named by keyword argument, which catches project-level helpers
    # such as `convert_to_monthly_partitions(table: :apples)` whatever their
    # name. Not bare `from:`/`to:`: `change_column_default :users, :status,
    # from: nil, to: "active"` would yield phantom tables.
    KEYWORD_TABLE_PATTERN = /\b(?:table|to_table|from_table):\s*[:"']?(\w+)/

    # Ruby `#` comments up to end of line, but not `#{}` interpolation.
    COMMENT_PATTERN = /#(?!\{).*/

    # AR class methods that strongly signal a constant is a model. Kept narrow:
    # `find`, `all`, `first`, `count`, `create`, `new`, `transaction`, `order`,
    # `includes` also exist on non-model constants (Time.new, File.find) and
    # would produce false positives.
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

      # An explanatory "# ALTER TABLE foo ..." or a commented-out create_table
      # reads exactly like the real thing to the patterns below.
      content = content.gsub(COMMENT_PATTERN, "")

      tables = []

      content.scan(SINGLE_TABLE_PATTERN) { |match| tables << match[0] }
      content.scan(DUAL_TABLE_PATTERN) { |match| tables.concat(match) }
      SQL_TABLE_PATTERNS.each do |pattern|
        content.scan(pattern) { |match| tables << match[0] }
      end
      content.scan(KEYWORD_TABLE_PATTERN) { |match| tables << match[0] }
      tables.uniq!

      # Model references are a guess (a constant answering these methods need
      # not be a model), so they only fill in when DDL and SQL found fewer
      # than 2 tables, and never take the total past 2.
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
