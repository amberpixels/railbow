# frozen_string_literal: true

require "stringio"
require_relative "../multi_db"
require_relative "../status/help"
require_relative "../status/printer"
require_relative "../status/section"

# Rails calls migrate_status once per database inside
# with_temporary_pool_for_each, for db:migrate:status and
# db:migrate:status:<database_name> alike. Wrapping that loop is what lets
# railbow render the databases together instead of one blind table each.
module Railbow
  module MigrateStatusFormatter
    # Rails 7.2 through 8.1 all route through here. Arguments pass verbatim so
    # Rails keeps applying its own defaults.
    def with_temporary_pool_for_each(*args, **kwargs, &block)
      Railbow::MultiDb.batch { super(*args, **kwargs, &block) }
    end

    def migrate_status
      return super if Railbow.plain?

      if Railbow::Params.help?
        Railbow::Status::Help.print if Railbow::MultiDb.claim_help
        return
      end

      batch = Railbow::MultiDb.current
      db_name = migration_connection_pool.db_config.name
      if batch && !Railbow::Params.db_included?(db_name)
        batch.skip(db_name)
        return
      end

      unless migration_connection_pool.schema_migration.table_exists?
        Kernel.abort "Schema migrations table does not exist yet."
      end

      # Outside the guard: an error here is Rails' own (a database that is
      # down) and must raise as it would without railbow. Captured while the
      # pool is still open, it is also the fallback.
      stock = railbow_capture_stdout { super }

      Railbow.guard(-> { $stdout.write(stock) }) do
        section = Railbow::Status::Section.new(migration_connection_pool)
        section.fallback_output = stock

        # No batch (a direct call, or a Rails that skips
        # with_temporary_pool_for_each): the section prints on its own.
        if batch
          batch.add(section)
        else
          Railbow::Status::Printer.new([section]).print
        end
      end
    end

    private

    def railbow_capture_stdout
      original = $stdout
      $stdout = StringIO.new
      yield
      $stdout.string
    ensure
      $stdout = original
    end
  end
end

ActiveRecord::Tasks::DatabaseTasks.prepend(Railbow::MigrateStatusFormatter)
