# frozen_string_literal: true

require "spec_helper"
require "mighost"
require "railbow/status/ghosts"

RSpec.describe Railbow::Status::Ghosts do
  def ghost_row(**attrs)
    Railbow::Status::Ghosts::Row.new(**attrs)
  end

  def orphan(version:, **attrs)
    Mighost::OrphanDetector::OrphanedMigration.new(version: version, **attrs)
  end

  describe ".tag" do
    it "prefers the superseded badge over branch and deletion" do
      tag = described_class.tag(ghost_row(
        superseded_by: "20260105130000",
        branch_name: "origin/apples",
        deleted_in_sha: "aabbccddeeff"
      ))
      expect(tag).to include("≡ 20260105130000")
      expect(tag).not_to include("⌥")
    end

    it "shows the branch badge when there is no superseder" do
      tag = described_class.tag(ghost_row(branch_name: "origin/apples", deleted_in_sha: "aabbccddeeff"))
      expect(tag).to include("⌥ origin/apples")
    end

    it "marks worktree branches with the worktree glyph" do
      tag = described_class.tag(ghost_row(branch_name: "apples", source: "worktree"))
      expect(tag).to include("⌥ₜapples")
    end

    it "falls back to the deletion commit with a short sha" do
      tag = described_class.tag(ghost_row(deleted_in_sha: "aabbccddeeff"))
      expect(tag).to include("✂ deleted in:aabbccdd")
    end

    it "returns nil when there is nothing to say" do
      expect(described_class.tag(ghost_row)).to be_nil
    end
  end

  describe ".display_name" do
    it "turns a recovered filename into a titleized name" do
      expect(described_class.display_name(ghost_row(filename: "20260101110000_add_apples_to_carts.rb")))
        .to eq("Add Apples To Carts")
    end
  end

  describe ".load" do
    before { allow(Mighost::API).to receive(:superseded_by).and_return(nil) }

    it "builds rows from detect results, carrying the classification" do
      allow(Mighost::API).to receive(:orphaned_migrations).and_return([
        orphan(version: "20260101110000", filename: "20260101110000_add_apples.rb",
          branch_name: nil, superseded_by: "20260105130000", deleted_in_sha: "aabbccddeeff")
      ])

      rows = described_class.load(["20260101110000"])
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

      rows = described_class.load(["20260101110000"])
      expect(rows["20260101110000"].filename).to eq("20260101110000_add_bananas.rb")
      expect(rows["20260101110000"].branch_name).to eq("origin/bananas")
      expect(rows["20260101110000"].superseded_by).to eq("20260109090000")
    end

    it "does not recover versions absent from detect (dismissed or hidden)" do
      allow(Mighost::API).to receive(:orphaned_migrations).and_return([])
      expect(Mighost::API).not_to receive(:find_or_recover_snapshot)

      expect(described_class.load(["20260101110000"])).to be_empty
    end

    it "drops a version whose live recovery finds nothing" do
      allow(Mighost::API).to receive(:orphaned_migrations).and_return([orphan(version: "20260101110000")])
      allow(Mighost::API).to receive(:find_or_recover_snapshot).and_return(nil)

      expect(described_class.load(["20260101110000"])).to be_empty
    end

    it "returns no rows when detect itself fails" do
      allow(Mighost::API).to receive(:orphaned_migrations).and_raise(StandardError)
      expect(described_class.load(["20260101110000"])).to eq({})
    end

    it "loads snapshot content only when requested" do
      allow(Mighost::API).to receive(:orphaned_migrations).and_return([
        orphan(version: "20260101110000", filename: "20260101110000_add_apples.rb")
      ])
      snapshot = Mighost::Snapshot.new(version: "20260101110000",
        filename: "20260101110000_add_apples.rb", content: "create_table :apples")
      allow(Mighost::API).to receive(:find_snapshot).with("20260101110000").and_return(snapshot)

      rows = described_class.load(["20260101110000"], with_content: true)
      expect(rows["20260101110000"].content).to eq("create_table :apples")

      expect(described_class.load(["20260101110000"])["20260101110000"].content).to be_nil
    end
  end
end
