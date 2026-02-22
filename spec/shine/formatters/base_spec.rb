# frozen_string_literal: true

require "spec_helper"

RSpec.describe Shine::Formatters::Base do
  subject(:formatter) { described_class.new }

  describe "#format_timing" do
    it "formats sub-millisecond times in microseconds" do
      result = formatter.format_timing(0.0005)
      expect(result).to include("500μs")
    end

    it "formats millisecond times" do
      result = formatter.format_timing(0.05)
      expect(result).to include("50.0ms")
    end

    it "colors timing in cyan" do
      expect(formatter.format_timing(0.05)).to start_with("\e[36m")
      expect(formatter.format_timing(0.2)).to start_with("\e[36m")
      expect(formatter.format_timing(1.0)).to start_with("\e[36m")
    end
  end

  describe "#format_timestamp" do
    it "formats a 14-char timestamp into readable form" do
      expect(formatter.format_timestamp("20240711185212")).to eq("2024-07-11 18:52:12")
    end

    it "returns non-14-char strings as-is" do
      expect(formatter.format_timestamp("short")).to eq("short")
      expect(formatter.format_timestamp("********")).to eq("********")
    end

    it "handles integer input" do
      expect(formatter.format_timestamp(20240711185212)).to eq("2024-07-11 18:52:12")
    end
  end

  describe "#emoji" do
    it "returns correct emojis for known types" do
      expect(formatter.emoji(:migrating)).to eq("🚀")
      expect(formatter.emoji(:migrated)).to eq("✅")
      expect(formatter.emoji(:reverting)).to eq("⏪")
      expect(formatter.emoji(:check)).to eq("✓")
    end

    it "returns empty string for unknown types" do
      expect(formatter.emoji(:unknown)).to eq("")
    end
  end

  describe "#render_table" do
    it "renders a table with styled header and data rows" do
      header = ["Name", "Value"]
      rows = [["foo", "bar"], ["baz", "qux"]]
      result = formatter.render_table(header, rows)
      lines = result.split("\n")

      expect(lines[0]).to include("Name")
      expect(lines[0]).to include("Value")
      expect(lines[1]).to include("foo")
      expect(lines.length).to eq(3) # header + 2 rows
    end

    it "renders identically with empty separators hash" do
      header = ["Name", "Value"]
      rows = [["foo", "bar"], ["baz", "qux"]]
      without = formatter.render_table(header, rows)
      with_empty = formatter.render_table(header, rows, separators: {})
      expect(with_empty).to eq(without)
    end

    it "inserts a separator line when separators hash has an entry" do
      header = ["Name", "Value"]
      rows = [["foo", "bar"], ["baz", "qux"], ["zip", "zap"]]
      result = formatter.render_table(header, rows, separators: {1 => "Mar 2023"})
      lines = result.split("\n")

      # header + separator + 3 rows = 5 lines
      expect(lines.length).to eq(5)
      expect(lines[2]).to include("\e[38;5;141mMar 2023\e[0m") # purple label
      expect(lines[2]).to include("\e[2m") # DIM dashes
      expect(lines[2]).to include("─")
    end

    it "handles ANSI-colored content for width calculation" do
      header = ["Status", "Name"]
      rows = [[formatter.green("up"), "test"]]
      result = formatter.render_table(header, rows)
      lines = result.split("\n")

      expect(lines.length).to eq(2) # header + 1 row
      expect(lines[1]).to include("test")
    end
  end

  describe "#green, #yellow, #red, #cyan, #bold" do
    it "wraps strings with ANSI codes" do
      expect(formatter.green("hi")).to eq("\e[32mhi\e[0m")
      expect(formatter.yellow("hi")).to eq("\e[33mhi\e[0m")
      expect(formatter.red("hi")).to eq("\e[31mhi\e[0m")
      expect(formatter.cyan("hi")).to eq("\e[36mhi\e[0m")
      expect(formatter.bold("hi")).to eq("\e[1mhi\e[0m")
    end
  end
end
