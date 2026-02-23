# frozen_string_literal: true

require "spec_helper"
require "benchmark"

# Minimal ActiveSupport shim for demodulize
unless String.method_defined?(:demodulize)
  class String
    def demodulize
      split("::").last
    end
  end
end

RSpec.describe Railbow::MigrationFormatter do
  let(:migration_class) do
    klass = Class.new do
      include Railbow::MigrationFormatter

      attr_reader :output

      def initialize
        @output = []
      end

      def write(text = "")
        @output << text
      end

      def puts(text)
        @output << text
      end
    end
    # Give it a name so announce can display it
    stub_const("TestMigration", klass)
    klass
  end

  subject(:migration) { migration_class.new }

  before { allow(Railbow).to receive(:plain?).and_return(false) }

  describe "#announce" do
    it "displays migrating with emoji and migration name" do
      migration.announce("migrating")
      line = migration.output.last

      expect(line).to include("🚀")
      expect(line).to include("TestMigration: migrating...")
      expect(line).to include("\e[36m") # cyan
    end

    it "displays migrated with formatted timing" do
      migration.announce("migrated (0.0070s)")
      line = migration.output.last

      expect(line).to include("✅")
      expect(line).to include("TestMigration: migrated")
      expect(line).to include("7.0ms")
    end

    it "displays reverting with yellow" do
      migration.announce("reverting")
      line = migration.output.last

      expect(line).to include("⏪")
      expect(line).to include("TestMigration: reverting...")
      expect(line).to include("\e[33m")
    end

    it "displays reverted with formatted timing" do
      migration.announce("reverted (0.0012s)")
      line = migration.output.last

      expect(line).to include("✅")
      expect(line).to include("TestMigration: reverted")
      expect(line).to include("1.2ms")
    end

    it "includes migration name for unrecognized messages" do
      migration.announce("something else")
      line = migration.output.last

      expect(line).to include("TestMigration: something else")
    end
  end

  describe "#say" do
    it "outputs with default prefix" do
      migration.say("hello")
      expect(migration.output.last).to eq("  hello")
    end

    it "outputs with subitem prefix" do
      migration.say("detail", :subitem)
      expect(migration.output.last).to eq("     detail")
    end
  end

  describe "#say_with_time" do
    it "outputs message with green checkmark and timing on one line" do
      result = migration.say_with_time("create_table(:products)") { 42 }

      expect(result).to eq(42)
      line = migration.output.find { |l| l.include?("create_table(:products)") }
      expect(line).to include("\e[32m✓\e[0m") # green checkmark
      expect(line).to include("→")
    end

    it "shows row count for integer results" do
      migration.say_with_time("do_something") { 5 }

      row_line = migration.output.find { |l| l.include?("5 rows") }
      expect(row_line).not_to be_nil
    end

    it "does not show row count for non-integer results" do
      migration.say_with_time("do_something") { "ok" }

      row_line = migration.output.find { |l| l.to_s.include?("rows") }
      expect(row_line).to be_nil
    end
  end
end
