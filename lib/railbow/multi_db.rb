# frozen_string_literal: true

module Railbow
  # Rails runs db:migrate:status once per database, inside
  # with_temporary_pool_for_each. Each call on its own cannot know whether more
  # databases are coming, so railbow wraps that loop: sections collect into the
  # open batch and the batch renders them together when the loop ends.
  #
  # A batch is inert unless something adds to it, so wrapping the other tasks
  # that share the same Rails helper (db:migrate, db:prepare) costs one object.
  module MultiDb
    KEY = :railbow_multi_db_batch

    class Batch
      attr_reader :git_cache

      def initialize
        @sections = []
        @skipped = []
        @git_cache = {}
        @help_shown = false
      end

      # A database excluded by RBW_DB. Recorded rather than dropped so the run
      # can say what it left out.
      def skip(name)
        @skipped << name.to_s
      end

      # Databases sharing a migrations path see the same files, so they merge
      # into one section that carries a status per database.
      def add(section)
        existing = @sections.find { |s| s.same_migrations?(section) }
        if existing
          existing.merge!(section)
        else
          @sections << section
        end
      end

      def claim_help
        return false if @help_shown

        @help_shown = true
      end

      def empty?
        @sections.empty? && @skipped.empty?
      end

      def flush
        return if empty?

        Railbow::Status::Printer.new(@sections, skipped: @skipped).print
        @sections = []
        @skipped = []
      end
    end

    module_function

    # Opens a batch for the duration of the block. The flush is in an ensure so
    # that a database aborting mid-run (a missing schema_migrations table, say)
    # still prints the sections collected before it.
    def batch
      previous = Thread.current[KEY]
      batch = Batch.new
      Thread.current[KEY] = batch
      begin
        yield
      ensure
        Thread.current[KEY] = previous
        batch.flush
      end
    end

    def current
      Thread.current[KEY]
    end

    # True the first time it is asked within a run. Without a batch every call
    # is its own run, so the answer is always true.
    def claim_help
      current ? current.claim_help : true
    end
  end
end
