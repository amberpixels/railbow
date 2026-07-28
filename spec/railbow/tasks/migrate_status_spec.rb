# frozen_string_literal: true

require "spec_helper"
require "active_record"
require "mighost"
require "stringio"

load File.expand_path("../../../lib/railbow/tasks/migrate_status.rake", __dir__)

RSpec.describe Railbow::MigrateStatusFormatter do
  subject(:helper) { helper_class.new }

  let(:helper_class) do
    Class.new do
      include Railbow::MigrateStatusFormatter

      attr_accessor :migration_connection_pool
    end
  end

  def ghost_row(**attrs)
    Railbow::MigrateStatusFormatter::GhostRow.new(**attrs)
  end

  def orphan(version:, **attrs)
    Mighost::OrphanDetector::OrphanedMigration.new(version: version, **attrs)
  end

  def stub_connection_pool(db_list, migrations: [])
    schema_migration = double(table_exists?: true)
    db_config = double(database: "testdb")
    migration_context = double(migrations_status: db_list, migrations: migrations)
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

  describe "#apply_branch_mask" do
    it "extracts the first capture group of the mask" do
      expect(helper.send(:apply_branch_mask, "PS-123/add-index", "(PS-[^/]+)/")).to eq("PS-123")
    end

    it "returns the branch unchanged when the mask is empty" do
      expect(helper.send(:apply_branch_mask, "feature/foo", "")).to eq("feature/foo")
    end

    it "returns the branch unchanged when the mask does not match" do
      expect(helper.send(:apply_branch_mask, "feature/foo", "(PS-[^/]+)/")).to eq("feature/foo")
    end

    it "returns the branch unchanged when the mask is an invalid regex" do
      expect(helper.send(:apply_branch_mask, "feature/foo", "([")).to eq("feature/foo")
    end
  end

  describe "#ghost_tag" do
    it "prefers the superseded badge over branch and deletion" do
      tag = helper.send(:ghost_tag, ghost_row(
        superseded_by: "20260105130000",
        branch_name: "origin/apples",
        deleted_in_sha: "aabbccddeeff"
      ))
      expect(tag).to include("≡ 20260105130000")
      expect(tag).not_to include("⌥")
    end

    it "shows the branch badge when there is no superseder" do
      tag = helper.send(:ghost_tag, ghost_row(branch_name: "origin/apples", deleted_in_sha: "aabbccddeeff"))
      expect(tag).to include("⌥ origin/apples")
    end

    it "marks worktree branches with the worktree glyph" do
      tag = helper.send(:ghost_tag, ghost_row(branch_name: "apples", source: "worktree"))
      expect(tag).to include("⌥ₜapples")
    end

    it "falls back to the deletion commit with a short sha" do
      tag = helper.send(:ghost_tag, ghost_row(deleted_in_sha: "aabbccddeeff"))
      expect(tag).to include("✂ deleted in:aabbccdd")
    end

    it "returns nil when there is nothing to say" do
      expect(helper.send(:ghost_tag, ghost_row)).to be_nil
    end
  end

  describe "#load_ghost_rows" do
    before { allow(Mighost::API).to receive(:superseded_by).and_return(nil) }

    it "builds rows from detect results, carrying the classification" do
      allow(Mighost::API).to receive(:orphaned_migrations).and_return([
        orphan(version: "20260101110000", filename: "20260101110000_add_apples.rb",
          branch_name: nil, superseded_by: "20260105130000", deleted_in_sha: "aabbccddeeff")
      ])

      rows = helper.send(:load_ghost_rows, ["20260101110000"])
      expect(rows.keys).to eq(["20260101110000"])
      expect(rows["20260101110000"].superseded_by).to eq("20260105130000")
      expect(rows["20260101110000"].deleted_in_sha).to eq("aabbccddeeff")
    end

    it "recovers live when detect lists a version without a snapshot filename" do
      allow(Mighost::API).to receive(:orphaned_migrations).and_return([
        orphan(version: "20260101110000")
      ])
      snapshot = Mighost::Snapshot.new(
        version: "20260101110000",
        filename: "20260101110000_add_bananas.rb",
        branch_name: "origin/bananas"
      )
      allow(Mighost::API).to receive(:find_or_recover_snapshot).with("20260101110000").and_return(snapshot)
      allow(Mighost::API).to receive(:superseded_by).with("20260101110000").and_return("20260109090000")

      rows = helper.send(:load_ghost_rows, ["20260101110000"])
      expect(rows["20260101110000"].filename).to eq("20260101110000_add_bananas.rb")
      expect(rows["20260101110000"].branch_name).to eq("origin/bananas")
      expect(rows["20260101110000"].superseded_by).to eq("20260109090000")
    end

    it "does not recover versions absent from detect (dismissed or hidden)" do
      allow(Mighost::API).to receive(:orphaned_migrations).and_return([])
      expect(Mighost::API).not_to receive(:find_or_recover_snapshot)

      rows = helper.send(:load_ghost_rows, ["20260101110000"])
      expect(rows).to be_empty
    end

    it "returns no rows when detect itself fails" do
      allow(Mighost::API).to receive(:orphaned_migrations).and_raise(StandardError)
      expect(helper.send(:load_ghost_rows, ["20260101110000"])).to eq({})
    end

    it "loads snapshot content only when requested" do
      allow(Mighost::API).to receive(:orphaned_migrations).and_return([
        orphan(version: "20260101110000", filename: "20260101110000_add_apples.rb")
      ])
      snapshot = Mighost::Snapshot.new(version: "20260101110000",
        filename: "20260101110000_add_apples.rb", content: "create_table :apples")
      allow(Mighost::API).to receive(:find_snapshot).with("20260101110000").and_return(snapshot)

      rows = helper.send(:load_ghost_rows, ["20260101110000"], with_content: true)
      expect(rows["20260101110000"].content).to eq("create_table :apples")

      expect(helper.send(:load_ghost_rows, ["20260101110000"])["20260101110000"].content).to be_nil
    end
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
end
