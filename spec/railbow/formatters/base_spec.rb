# frozen_string_literal: true

require "spec_helper"

RSpec.describe Railbow::Formatters::Base do
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

  describe "#green, #yellow, #red, #cyan, #bold" do
    it "wraps strings with ANSI codes" do
      expect(formatter.green("hi")).to eq("\e[32mhi\e[0m")
      expect(formatter.yellow("hi")).to eq("\e[33mhi\e[0m")
      expect(formatter.red("hi")).to eq("\e[31mhi\e[0m")
      expect(formatter.cyan("hi")).to eq("\e[36mhi\e[0m")
      expect(formatter.bold("hi")).to eq("\e[1mhi\e[0m")
    end
  end

  describe "#table_color" do
    it "returns a deterministic color code for a table name" do
      color1 = formatter.table_color("products")
      color2 = formatter.table_color("products")
      expect(color1).to eq(color2)
    end

    it "returns a value from TABLE_PALETTE" do
      color = formatter.table_color("users")
      expect(Railbow::Formatters::Base::TABLE_PALETTE).to include(color)
    end
  end

  describe "#table_tag" do
    it "returns a colored bullet with table name" do
      tag = formatter.table_tag("products")
      expect(tag).to include("● products")
      expect(tag).to match(/\e\[38;5;\d+m/)
      expect(tag).to end_with("\e[0m")
    end
  end

  describe "#table_tags" do
    it "returns empty string for nil" do
      expect(formatter.table_tags(nil)).to eq("")
    end

    it "returns empty string for empty array" do
      expect(formatter.table_tags([])).to eq("")
    end

    it "joins multiple tags with spaces" do
      result = formatter.table_tags(["products", "users"])
      expect(result).to include("● products")
      expect(result).to include("● users")
    end
  end
end
