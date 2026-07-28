# frozen_string_literal: true

require "spec_helper"
require "active_record"
require "stringio"
require "support/status_fixture"

load File.expand_path("../../lib/railbow/tasks/migrate_status.rake", __dir__)

RSpec.describe "multi-database db:migrate:status" do
  include StatusFixture

  # Stands in for Rails' DatabaseTasks: with_temporary_pool_for_each walks the
  # configured databases, pointing migration_connection_pool at each in turn,
  # exactly as activerecord's databases.rake does. Railbow is prepended on top,
  # the same way the railtie installs it.
  let(:rails_double) do
    Class.new do
      attr_accessor :pools, :migration_connection_pool

      def with_temporary_pool_for_each(env: nil, name: nil, clobber: false)
        pools.each do |pool|
          next if name && pool.db_config.name != name
          self.migration_connection_pool = pool
          yield pool
        end
      end
    end
  end

  let(:helper_class) { Class.new(rails_double) { prepend Railbow::MigrateStatusFormatter } }
  let(:helper) { helper_class.new }

  def pool_double(name:, statuses:, path: "db/migrate", database: nil, migrations: [])
    double(
      schema_migration: double(table_exists?: true),
      db_config: double(name: name, database: database || "#{name}-dev"),
      migration_context: double(migrations_status: statuses, migrations: migrations,
        migrations_paths: Array(path))
    )
  end

  # Mirrors databases.rake: the per-database loop with migrate_status inside.
  def run(pools, name: nil)
    helper.pools = pools
    capture_stdout do
      helper.with_temporary_pool_for_each(name: name) { helper.migrate_status }
    end
  end

  before do
    allow(Railbow).to receive(:plain?).and_return(false)
    allow(Railbow::Params).to receive(:since).and_return("all")
    allow(Mighost).to receive(:enabled?).and_return(false) if defined?(Mighost)
    isolate_config
    # Display modes are stated per example rather than inherited from the gem
    # defaults, so these specs keep covering every mode whichever one ships as
    # the default.
    allow(Railbow::Params).to receive(:db_focus?).and_return(false)
    stub_git
  end

  let(:primary) do
    pool_double(name: "primary", statuses: [["up", "20260101000001", "Add Apples"]])
  end
  let(:secondary) do
    pool_double(name: "log", path: "db/migrate_log",
      statuses: [["up", "20260101000002", "Add Bananas"]])
  end

  describe "one database" do
    it "renders exactly as a single-database app always has" do
      output = run([primary])

      expect(output).to include("📊 Database:")
      expect(output).not_to include("databases")
      expect(output).not_to include("────")
    end

    it "keeps db:migrate:status:<name> a single-database render" do
      output = run([primary, secondary], name: "log")

      expect(output).to include("Add Bananas")
      expect(output).not_to include("Add Apples")
      expect(output).to include("📊 Database:")
      expect(output).not_to include("2 databases")
    end
  end

  describe "several databases" do
    it "prints one overview line and a section per database" do
      output = run([primary, secondary])

      expect(output).to include("2 databases")
      expect(output.scan("📊").size).to eq(1)
      expect(output).to include("primary · primary-dev")
      expect(output).to include("log · log-dev")
      expect(output).to include("Add Apples").and include("Add Bananas")
    end

    it "names the database by its config name, not its database name" do
      output = run([primary, secondary])

      expect(output).to include("primary, log")
    end

    it "lines the tables up by sharing column widths" do
      wide = pool_double(name: "primary",
        statuses: [["up", "20260101000001", "A migration with a very long name indeed"]])
      narrow = pool_double(name: "log", path: "db/migrate_log",
        statuses: [["up", "20260101000002", "Short"]])

      lines = run([wide, narrow]).lines.select { |l| l.include?("│") }
      widths = lines.map { |l| Railbow::Formatters::Base.new.strip_ansi(l).rstrip.length }

      # Every row, in both tables, reaches the same last-column boundary.
      expect(widths.uniq.size).to eq(1)
    end
  end

  describe "databases sharing a migrations path" do
    let(:shard_a) do
      pool_double(name: "primary", statuses: [
        ["up", "20260101000001", "Add Apples"],
        ["up", "20260101000002", "Add Bananas"]
      ])
    end
    let(:shard_b) do
      pool_double(name: "primary_shard_one", statuses: [
        ["up", "20260101000001", "Add Apples"],
        ["down", "20260101000002", "Add Bananas"]
      ])
    end

    it "merges them into one section with a status per database" do
      output = run([shard_a, shard_b])

      expect(output).to include("primary + primary_shard_one")
      expect(output.scan("Add Apples").size).to eq(1)

      row = output.lines.find { |l| l.include?("Add Bananas") }
      expect(row).to include("↑↑").and include("↓↓")
    end

    it "resolves status aliases itself, since no whole-cell alias can match a cluster" do
      row = run([shard_a, shard_b]).lines.find { |l| l.include?("Add Apples") }

      plain = Railbow::Formatters::Base.new.strip_ansi(row)
      expect(plain).to start_with(" ↑↑ ↑↑")
      expect(plain).not_to include("up")
    end

    it "marks a version one shard has never seen" do
      only_a = pool_double(name: "primary", statuses: [
        ["up", "20260101000001", "Add Apples"],
        ["up", "20260101000009", "Add Cherries"]
      ])
      only_b = pool_double(name: "primary_shard_one", statuses: [
        ["up", "20260101000001", "Add Apples"]
      ])

      row = run([only_a, only_b]).lines.find { |l| l.include?("Add Cherries") }
      expect(Railbow::Formatters::Base.new.strip_ansi(row)).to include("↑↑ ·")
    end

    it "greys out a row only when it is pending everywhere" do
      section_rows = run([shard_a, shard_b]).lines
      half_pending = section_rows.find { |l| l.include?("Add Bananas") }

      expect(half_pending).not_to include(Railbow::Table::Renderer::DIMMED_FG)
    end
  end

  describe "quiet databases" do
    let(:quiet) do
      pool_double(name: "cache", path: "db/cache_migrate",
        statuses: [["up", "20200101000001", "Create Solid Cache"]])
    end

    before { allow(Railbow::Params).to receive(:since).and_return("70d") }

    it "collapses to a single line instead of an empty table" do
      output = run([primary, quiet])

      expect(output).to include("⋯ cache · 1 migration, all applied")
      expect(output).not_to include("No migrations in the selected period")
    end

    it "reports pending migrations hidden outside the window" do
      pending_outside = pool_double(name: "cache", path: "db/cache_migrate",
        statuses: [["down", "20200101000001", "Create Solid Cache"]])

      expect(run([primary, pending_outside])).to include("1 pending outside the 70d window")
    end

    it "renders the full table when RBW_DB=full" do
      allow(Railbow::Params).to receive(:db_full?).and_return(true)

      output = run([primary, quiet])
      expect(output).not_to include("⋯ cache")
      expect(output).to include("Create Solid Cache")
    end

    it "does not collapse a lone database" do
      expect(run([quiet])).to include("Create Solid Cache")
    end

    # "3 of 5" would read as "3 fell inside the window". They did not: the
    # window found nothing and the floor took the newest three.
    it "says the count is a tail when the floor overrode the window" do
      allow(Railbow::Params).to receive(:since_min).and_return(3)
      allow(Railbow::Params).to receive(:db_full?).and_return(true)

      old = pool_double(name: "log", path: "db/migrate_log",
        statuses: (1..5).map { |i| ["up", format("202001010000%02d", i), "Add Apples #{i}"] })

      output = run([primary, old])
      expect(output).to include("last 3 of 5")
      expect(output).to include("Add Apples 5")
      expect(output).not_to include("Add Apples 1 ")
    end

    # The floor tops a section back up to RBW_SINCE_MIN rows, but a section
    # whose rows all come from outside the window still has nothing recent to
    # report, so it must still collapse rather than printing a stale table.
    it "collapses a stale database even when the floor would give it rows" do
      allow(Railbow::Params).to receive(:since_min).and_return(10)

      output = run([primary, quiet])
      expect(output).to include("⋯ cache · 1 migration, all applied")
      expect(output).not_to include("Create Solid Cache")
    end
  end

  describe "RBW_DB=focus" do
    it "is the shipped default" do
      allow(Railbow::Params).to receive(:db_focus?).and_call_original
      Railbow::Config.reset!

      expect(Railbow::Params.db_focus?).to be(true)
    end

    before { allow(Railbow::Params).to receive(:db_focus?).and_return(true) }

    it "expands the first database and summarizes the rest" do
      output = run([primary, secondary])

      expect(output).to include("Add Apples")
      expect(output).not_to include("Add Bananas")
      expect(output).to include("⋯ log · 1 migration, all applied")
    end

    # The whole point of the summary is to hide what you do not need to act on.
    # Pending migrations are the opposite of that.
    it "expands a summarized database that has migrations pending" do
      pending_log = pool_double(name: "log", path: "db/migrate_log", statuses: [
        ["up", "20260101000002", "Add Bananas"],
        ["down", "20260101000003", "Add Dates"]
      ])

      output = run([primary, pending_log])
      expect(output).to include("Add Dates")
      expect(output).to include("log · log-dev")
      expect(output).not_to include("⋯ log")
    end

    it "still expands everything under RBW_DB=full" do
      allow(Railbow::Params).to receive(:db_full?).and_return(true)

      output = run([primary, secondary])
      expect(output).to include("Add Bananas")
      expect(output).not_to include("⋯ log")
    end

    # Focus shapes the sectioned view. A merged table exists to hold every
    # database at once, so focus must not quietly empty it.
    it "does not drop databases from an inline run" do
      allow(Railbow::Params).to receive(:db_inline?).and_return(true)

      output = run([primary, secondary])
      expect(output).to include("Add Apples").and include("Add Bananas")
      expect(output).not_to include("⋯ log")
    end
  end

  describe "RBW_DB=inline" do
    before { allow(Railbow::Params).to receive(:db_inline?).and_return(true) }

    let(:early_raw) do
      pool_double(name: "log", path: "db/migrate_log", statuses: [
        ["up", "20260101000000", "Add Cherries"],
        ["down", "20260101000003", "Add Dates"]
      ])
    end

    it "interleaves the databases into one table ordered by version" do
      output = run([primary, early_raw])
      names = output.lines.filter_map { |l| l[/Add \w+/] }

      expect(names).to eq(["Add Cherries", "Add Apples", "Add Dates"])
    end

    it "labels every row with its database" do
      output = run([primary, early_raw])

      expect(output).to include("Db")
      expect(output.lines.find { |l| l.include?("Add Apples") }).to include("● primary")
      expect(output.lines.find { |l| l.include?("Add Cherries") }).to include("● log")
    end

    # RBW_DB=full means draw every database. A stale one whose rows exist only
    # because of the SINCE_MIN floor still has rows, so it belongs in the
    # merged table rather than in a summary line below it.
    it "keeps a stale database in the merged table under RBW_DB=full" do
      allow(Railbow::Params).to receive(:db_full?).and_return(true)
      allow(Railbow::Params).to receive(:since).and_return("70d")
      allow(Railbow::Params).to receive(:since_min).and_return(10)

      recent = pool_double(name: "primary",
        statuses: [["up", Time.now.strftime("%Y%m%d%H%M%S"), "Add Apples"]])
      stale = pool_double(name: "cache", path: "db/cache_migrate",
        statuses: [["up", "20200101000001", "Create Solid Cache"]])

      output = run([recent, stale])
      expect(output).to include("Create Solid Cache")
      expect(output).not_to include("⋯ cache")
    end

    it "re-keys row markers to the merged order" do
      row = run([primary, early_raw]).lines.find { |l| l.include?("Add Dates") }

      # Add Dates is pending, and is the last row after sorting - the dim marker
      # has to follow it across the reorder rather than staying on index 1.
      expect(row).to include(Railbow::Table::Renderer::DIMMED_FG)
    end
  end

  describe "RBW_DB filtering" do
    it "keeps only the named databases and says what it dropped" do
      allow(Railbow::Params).to receive(:db_included?) { |n| n == "log" }

      output = run([primary, secondary])
      expect(output).to include("Add Bananas")
      expect(output).not_to include("Add Apples")
      expect(output).to include("⋯ 1 database hidden: primary")
    end
  end

  describe "the batch itself" do
    it "reuses one GitData per migrations directory across databases" do
      shard_a = pool_double(name: "primary", statuses: [["up", "20260101000001", "Add Apples"]],
        migrations: [StatusFixture::MigrationDouble.new("20260101000001", "db/migrate/20260101000001_add_apples.rb")])
      shard_b = pool_double(name: "primary_shard_one", statuses: [["up", "20260101000001", "Add Apples"]],
        migrations: [StatusFixture::MigrationDouble.new("20260101000001", "db/migrate/20260101000001_add_apples.rb")])

      expect(Railbow::Status::GitData).to receive(:new).once.and_call_original

      run([shard_a, shard_b])
    end

    it "prints the sections collected before a database aborts" do
      broken = double(
        schema_migration: double(table_exists?: false),
        db_config: double(name: "log", database: "log-dev"),
        migration_context: double(migrations_status: [], migrations: [], migrations_paths: ["db/migrate_log"])
      )

      # Captured by hand: the abort escapes before capture_stdout can return,
      # and what was printed before it is exactly what this asserts on.
      helper.pools = [primary, broken]
      io = StringIO.new
      original = $stdout
      original_err = $stderr
      $stdout = io
      $stderr = StringIO.new # abort's own message; not what this asserts on
      begin
        expect { helper.with_temporary_pool_for_each { helper.migrate_status } }
          .to raise_error(SystemExit)
      ensure
        $stdout = original
        $stderr = original_err
      end

      expect(io.string).to include("Add Apples")
    end

    it "renders immediately when no batch is open" do
      helper.migration_connection_pool = primary

      expect(capture_stdout { helper.migrate_status }).to include("Add Apples")
    end

    it "shows the help once for the whole run, not once per database" do
      allow(Railbow::Params).to receive(:help?).and_return(true)

      output = run([primary, secondary])
      expect(output.scan("Enhanced db:migrate:status").size).to eq(1)
    end
  end
end
