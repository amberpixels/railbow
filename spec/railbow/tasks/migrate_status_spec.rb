# frozen_string_literal: true

require "spec_helper"
require "active_record"
require "mighost"
require "stringio"
require "support/status_fixture"

load File.expand_path("../../../lib/railbow/tasks/migrate_status.rake", __dir__)

RSpec.describe Railbow::MigrateStatusFormatter do
  include StatusFixture

  subject(:helper) { helper_class.new }

  before { isolate_config }

  let(:helper_class) do
    Class.new do
      include Railbow::MigrateStatusFormatter

      attr_accessor :migration_connection_pool
    end
  end

  def orphan(version:, **attrs)
    Mighost::OrphanDetector::OrphanedMigration.new(version: version, **attrs)
  end

  def stub_connection_pool(db_list, migrations: [], name: "primary", migrations_paths: ["db/migrate"])
    schema_migration = double(table_exists?: true)
    db_config = double(database: "testdb", name: name)
    migration_context = double(migrations_status: db_list, migrations: migrations,
      migrations_paths: migrations_paths)
    helper.migration_connection_pool =
      double(schema_migration: schema_migration, db_config: db_config, migration_context: migration_context)
  end

  def render_status
    captured = StringIO.new
    original = $stdout
    $stdout = captured
    helper.migrate_status
    captured.string
  ensure
    $stdout = original
  end

  describe "#migrate_status ghost rendering" do
    let(:no_file_name) { "********** NO FILE **********" }
    let(:db_list) do
      [
        ["up", "20260101000001", no_file_name],
        ["up", "20260101000002", no_file_name]
      ]
    end

    before do
      allow(Railbow).to receive(:plain?).and_return(false)
      allow(Railbow::Params).to receive(:since).and_return("all")

      stub_connection_pool(db_list)

      allow(Mighost).to receive(:enabled?).and_return(true)
      allow(Mighost::API).to receive(:superseded_by).and_return(nil)
    end

    it "does not leak the previous ghost's branch badge onto a branchless ghost" do
      allow(Mighost::API).to receive(:orphaned_migrations).and_return([
        orphan(version: "20260101000001", filename: "20260101000001_add_apples.rb",
          branch_name: "origin/apples"),
        orphan(version: "20260101000002", filename: "20260101000002_add_bananas.rb",
          branch_name: nil)
      ])

      lines = render_status.lines
      first = lines.find { |l| l.include?("Add Apples") }
      second = lines.find { |l| l.include?("Add Bananas") }
      expect(first).to include("⌥ origin/apples")
      expect(second).not_to include("⌥")
    end

    it "renders a superseded ghost with the calm glyph and successor badge" do
      allow(Mighost::API).to receive(:orphaned_migrations).and_return([
        orphan(version: "20260101000001", filename: "20260101000001_add_apples.rb",
          superseded_by: "20260101000002"),
        orphan(version: "20260101000002", filename: "20260101000002_add_bananas.rb",
          branch_name: "origin/bananas")
      ])

      output = render_status
      line = output.lines.find { |l| l.include?("Add Apples") }
      expect(line).to include("🪦")
      expect(line).to include("≡ 20260101000002")
      expect(line).not_to include("👻")
    end

    it "renders ghosts suppressed by mighost as plain NO FILE without recovery" do
      allow(Mighost::API).to receive(:orphaned_migrations).and_return([])
      expect(Mighost::API).not_to receive(:find_or_recover_snapshot)

      output = render_status
      expect(output).to include("NO FILE")
      expect(output).not_to include("👻")
    end
  end

  describe "#migrate_status down rendering" do
    before do
      allow(Railbow).to receive(:plain?).and_return(false)
      allow(Railbow::Params).to receive(:since).and_return("all")
      allow(Mighost).to receive(:enabled?).and_return(false) if defined?(Mighost)

      stub_connection_pool([
        ["up", "20260101000001", "Add Apples"],
        ["down", "20260101000002", "Add Bananas"]
      ])
    end

    it "greys out the whole row of a migration that is not applied" do
      lines = render_status.lines
      applied = lines.find { |l| l.include?("Add Apples") }
      pending_row = lines.find { |l| l.include?("Add Bananas") }

      expect(pending_row).to include(Railbow::Table::Renderer::DIMMED_FG)
      expect(applied).not_to include(Railbow::Table::Renderer::DIMMED_FG)
    end
  end

  describe "#migrate_status empty states" do
    before do
      allow(Railbow).to receive(:plain?).and_return(false)
      allow(Mighost).to receive(:enabled?).and_return(false) if defined?(Mighost)
    end

    it "reports a database with no migrations at all" do
      allow(Railbow::Params).to receive(:since).and_return("all")
      stub_connection_pool([])

      expect(render_status).to include("No migrations found")
    end

    it "reports how many migrations the since filter hid" do
      allow(Railbow::Params).to receive(:since).and_return("1d")
      allow(Railbow::Params).to receive(:since_min).and_return(0)
      stub_connection_pool([["up", "20200101000001", "Add Apples"]])

      output = render_status
      expect(output).to include("1 older migrations hidden - SINCE=1d")
      expect(output).to include("No migrations in the selected period")
    end
  end

  # The time window is a soft limit: it never hides so much that the table
  # stops being useful. A database with a handful of migrations shows all of
  # them however old they are, rather than reporting an empty period.
  describe "#migrate_status minimum row floor" do
    def old_migrations(count)
      (1..count).map { |i| ["up", format("202001010000%02d", i), "Add Apples #{i}"] }
    end

    before do
      allow(Railbow).to receive(:plain?).and_return(false)
      allow(Railbow::Params).to receive(:since).and_return("70d")
      allow(Mighost).to receive(:enabled?).and_return(false) if defined?(Mighost)
    end

    it "shows every migration when there are fewer than the floor" do
      allow(Railbow::Params).to receive(:since_min).and_return(10)
      stub_connection_pool(old_migrations(5))

      output = render_status
      5.times { |i| expect(output).to include("Add Apples #{i + 1}") }
      expect(output).not_to include("hidden")
      expect(output).not_to include("No migrations in the selected period")
    end

    it "stops at the floor and reports the rest as hidden" do
      allow(Railbow::Params).to receive(:since_min).and_return(10)
      stub_connection_pool(old_migrations(15))

      output = render_status
      expect(output).to include("5 older migrations hidden - SINCE=70d, showing the last 10")
      expect(output).to include("Add Apples 15")
      expect(output).not_to include("Add Apples 5\e")
    end

    it "keeps the newest migrations, not the oldest" do
      allow(Railbow::Params).to receive(:since_min).and_return(3)
      stub_connection_pool(old_migrations(5))

      output = render_status
      expect(output).to include("Add Apples 3").and include("Add Apples 5")
      expect(output).not_to include("Add Apples 1 ")
    end

    it "says nothing about a floor that never came into play" do
      allow(Railbow::Params).to receive(:since_min).and_return(10)
      stub_connection_pool([["up", Time.now.strftime("%Y%m%d%H%M%S"), "Add Apples"]])

      expect(render_status).not_to include("showing the last")
    end

    it "is disabled by RBW_SINCE_MIN=0" do
      allow(Railbow::Params).to receive(:since_min).and_return(0)
      stub_connection_pool(old_migrations(5))

      expect(render_status).to include("No migrations in the selected period")
    end
  end
end
