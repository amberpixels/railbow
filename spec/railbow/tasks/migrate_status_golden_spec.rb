# frozen_string_literal: true

require "spec_helper"
require "active_record"
require "support/status_fixture"

load File.expand_path("../../../lib/railbow/tasks/migrate_status.rake", __dir__)

# Pins the full single-database render byte for byte.
#
# Multi-database support rests on one promise: a single-database app sees output
# identical to what it saw before. This spec is that promise, and it is deliberately
# brittle - it fails on any change to colors, spacing, glyphs or column order.
#
# When a change to the render is intentional, regenerate rather than hand-edit:
#   REGENERATE_GOLDEN=1 bundle exec rspec spec/railbow/tasks/migrate_status_golden_spec.rb
# then read the diff (`git diff --word-diff` on the fixture) and confirm every
# byte that moved was meant to move.
RSpec.describe "db:migrate:status golden output" do
  include StatusFixture

  let(:golden) { golden_path("single_db_status.txt") }

  subject(:helper) do
    Class.new do
      include Railbow::MigrateStatusFormatter

      attr_accessor :migration_connection_pool
    end.new
  end

  before do
    isolate_config
    allow(Railbow).to receive(:plain?).and_return(false)
    # "all" keeps the render independent of the day it runs; the since filter
    # has its own coverage elsewhere.
    allow(Railbow::Params).to receive(:since).and_return("all")
    allow(Mighost).to receive(:enabled?).and_return(false) if defined?(Mighost)
    stub_git
  end

  def render(dir)
    helper.migration_connection_pool = double(
      schema_migration: double(table_exists?: true),
      db_config: double(database: "railbow_test", name: "primary"),
      migration_context: double(migrations_status: fixture_db_list, migrations: migration_doubles(dir),
        migrations_paths: [dir])
    )
    capture_stdout { helper.migrate_status }
  end

  it "renders the default configuration unchanged" do
    output = with_migration_files { |dir| render(dir) }

    File.write(golden, output) if ENV["REGENERATE_GOLDEN"]

    expect(File.exist?(golden)).to be(true),
      "golden fixture missing - run with REGENERATE_GOLDEN=1 to create it"
    expect(output).to eq(File.read(golden))
  end

  # The golden file is only a guard if it actually covers the render. These
  # assert the fixture exercises each feature, so a regeneration that silently
  # drops one (an exception swallowed into an empty column, say) still fails.
  describe "coverage of the render path" do
    let(:output) { with_migration_files { |dir| render(dir) } }

    it "covers the calendar separator" do
      expect(output).to include("Mar 2026")
    end

    it "covers table detection" do
      expect(output).to include("● animals").and include("● veterinary_appointments")
    end

    it "covers the landed badge" do
      expect(output).to include("↪ Mar 04")
    end

    it "covers the author column, in the default short format" do
      expect(output).to include("Te D").and include("Ot D")
    end

    it "covers highlighted, dimmed and NO FILE rows" do
      expect(output).to include(Railbow::Table::Renderer::WHITE)
      expect(output).to include(Railbow::Table::Renderer::DIMMED_FG)
      expect(output).to include("NO FILE")
    end
  end
end
