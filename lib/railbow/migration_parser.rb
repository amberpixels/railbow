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

    # A table name with an optional schema: `events` or `reporting.events`.
    QUALIFIED_NAME = '(?:\w+\.)?\w+'

    # A table argument: a symbol, or a string that may carry a schema. Two
    # captures, one of them nil.
    TABLE_ARG = /(?::(\w+)|"(#{QUALIFIED_NAME}))/

    # Dual-table methods are included here too: their first argument is always a
    # table, even when the second is passed as `to_table:` instead of positionally.
    SINGLE_TABLE_PATTERN = /\b(?:#{(SINGLE_TABLE_METHODS + DUAL_TABLE_METHODS).join("|")})\s+#{TABLE_ARG}/
    DUAL_TABLE_PATTERN = /\b(?:#{DUAL_TABLE_METHODS.join("|")})\s+#{TABLE_ARG}["\s,]+#{TABLE_ARG}/

    # One part of a SQL name, quoted or bare. The backslash is the one a Ruby
    # string puts before an inner quote. A closing quote is only taken with its
    # opening one, so `"... FROM events".squish` does not read as a schema.
    SQL_NAME_PART = /(?:\\?["'`]\w+\\?["'`]|\\?["'`]?\w+)/
    SQL_TABLE = /(#{SQL_NAME_PART}(?:\.#{SQL_NAME_PART})?)/
    SQL_QUOTING = "\\\\\"'`"

    SQL_TABLE_PATTERNS = [
      /\bUPDATE\s+#{SQL_TABLE}/i,
      /\bINSERT\s+INTO\s+#{SQL_TABLE}/i,
      /\bDELETE\s+FROM\s+#{SQL_TABLE}/i,
      /\bALTER\s+TABLE\s+(?:IF\s+EXISTS\s+)?(?:ONLY\s+)?#{SQL_TABLE}/i,
      /\bTRUNCATE\s+(?:TABLE\s+)?#{SQL_TABLE}/i,
      /\bDROP\s+TABLE\s+(?:IF\s+EXISTS\s+)?#{SQL_TABLE}/i,
      /\bCREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?#{SQL_TABLE}/i,
      # The index name is optional in Postgres, hence the optional word before ON.
      /\bCREATE\s+(?:UNIQUE\s+)?INDEX\s+(?:CONCURRENTLY\s+)?(?:IF\s+NOT\s+EXISTS\s+)?(?:\S+\s+)?ON\s+(?:ONLY\s+)?#{SQL_TABLE}/i,
      /\bCREATE\s+(?:OR\s+REPLACE\s+)?(?:TEMP(?:ORARY)?\s+)?(?:MATERIALIZED\s+)?VIEW\s+(?:IF\s+NOT\s+EXISTS\s+)?#{SQL_TABLE}/i
    ].freeze

    # A table named by keyword argument, which catches project-level helpers
    # such as `convert_to_monthly_partitions(table: :apples)` whatever their
    # name. Not bare `from:`/`to:`: `change_column_default :users, :status,
    # from: nil, to: "active"` would yield phantom tables. Only a quoted value
    # may carry a schema, so `table: apples.to_s` still reads as `apples`.
    KEYWORD_TABLE_PATTERN = /\b(?:table|to_table|from_table):\s*(?:["'](#{QUALIFIED_NAME})|:?(\w+))/

    # Postgres resolves a bare name to this schema, so the prefix says nothing.
    DEFAULT_SCHEMA_PREFIX = "public."

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

      content.scan(SINGLE_TABLE_PATTERN) { |match| tables.concat(match.compact) }
      content.scan(DUAL_TABLE_PATTERN) { |match| tables.concat(match.compact) }
      SQL_TABLE_PATTERNS.each do |pattern|
        content.scan(pattern) { |match| tables << match[0].delete(SQL_QUOTING) }
      end
      content.scan(KEYWORD_TABLE_PATTERN) { |match| tables.concat(match.compact) }
      tables.map! { |table| table.delete_prefix(DEFAULT_SCHEMA_PREFIX) }
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
