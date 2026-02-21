# frozen_string_literal: true

require_relative "../formatters/base"

# Override DatabaseTasks.migrate_status which is called by both
# db:migrate:status and db:migrate:status:<database_name> tasks.
module Shine
  module MigrateStatusFormatter
    def migrate_status
      unless migration_connection_pool.schema_migration.table_exists?
        Kernel.abort "Schema migrations table does not exist yet."
      end

      formatter = Shine::Formatters::Base.new

      db_name = migration_connection_pool.db_config.database
      puts "\n#{formatter.emoji(:status)} Database: #{formatter.cyan(db_name)}"
      puts

      db_list = migration_connection_pool.migration_context.migrations_status

      if db_list.empty?
        puts formatter.yellow("  No migrations found")
        return
      end

      header = ["Status", "Migration ID", "Created At", "Migration Name"]
      rows = db_list.map do |status, version, name|
        colored_status = case status
        when "up"   then formatter.green_bold("up")
        when "down" then formatter.yellow_bold("down")
        else status
        end

        [colored_status, version.to_s, formatter.format_timestamp(version), name]
      end

      puts formatter.render_table(header, rows)
    end
  end
end

ActiveRecord::Tasks::DatabaseTasks.prepend(Shine::MigrateStatusFormatter)
