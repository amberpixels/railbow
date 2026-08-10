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

  describe "#format_date" do
    it "formats full mode (default)" do
      expect(formatter.format_date("20240711185212", "full")).to eq("2024-07-11 18:52:12")
    end

    it "formats short mode" do
      expect(formatter.format_date("20260130120854", "short")).to eq("Jan 30")
    end

    it "formats rel mode" do
      result = formatter.format_date("20240711185212", "rel")
      expect(result).to match(/ago|just now/)
    end

    it "formats custom strftime" do
      expect(formatter.format_date("20260130120854", "custom(%b %d, %Y)")).to eq("Jan 30, 2026")
    end

    it "returns non-14-char strings as-is" do
      expect(formatter.format_date("short", "full")).to eq("short")
    end

    it "defaults mode to full" do
      expect(formatter.format_date("20240711185212")).to eq("2024-07-11 18:52:12")
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

  describe "#name_with_tags_fitted" do
    # A name cell as the status table composes it: tags padded flush against
    # the right edge of a 60 wide column.
    def cell(name, tags, width: 60)
      tags_width = formatter.display_width(formatter.strip_ansi(tags))
      padding = width - formatter.display_width(name) - tags_width
      "#{name}#{" " * [padding, 2].max}#{tags}"
    end

    let(:branch) { formatter.diff_tag_branch("PS-2569") }
    let(:tagged) { cell("Readd goal tracking widgets", branch) }

    def plain(str) = formatter.strip_ansi(str)

    it "keeps the tag and shortens the name" do
      result = formatter.name_with_tags_fitted(tagged, 40)

      expect(plain(result)).to include("⎇ PS-2569")
      expect(plain(result)).to start_with("Readd goal")
      expect(formatter.display_width(plain(result))).to eq(40)
    end

    it "keeps a name that still fits intact, with no stray ellipsis" do
      result = formatter.name_with_tags_fitted(tagged, 44)

      expect(plain(result)).to eq("Readd goal tracking widgets        ⎇ PS-2569")
    end

    it "leaves a cell that already fits alone" do
      expect(formatter.name_with_tags_fitted(tagged, 60)).to eq(tagged)
    end

    it "keeps the tag flush against the right edge" do
      result = formatter.name_with_tags_fitted(tagged, 34)

      expect(plain(result)).to end_with("⎇ PS-2569")
    end

    it "keeps every tag when a cell carries more than one" do
      tags = [formatter.landed_tag(Date.new(2026, 8, 8)), branch].join(" ")
      result = formatter.name_with_tags_fitted(cell("Readd goal tracking widgets", tags), 44)

      expect(plain(result)).to include("↪ Aug 08")
      expect(plain(result)).to include("⎇ PS-2569")
    end

    it "drops the tags when keeping them would leave no room for the name" do
      wide = cell("Readd goal tracking widgets", formatter.diff_tag_branch("feature/quite-a-long-branch"))
      result = formatter.name_with_tags_fitted(wide, 34)

      expect(plain(result)).to eq("Readd goal tracking widgets")
    end

    it "falls back to plain truncation for an untagged name" do
      result = formatter.name_with_tags_fitted("Add a migration name long enough to overflow", 24)

      expect(plain(result)).to eq("Add a migration name ...")
    end

    it "never renders wider than the width it was given" do
      [60, 44, 34, 24, 16].each do |width|
        result = formatter.name_with_tags_fitted(tagged, width)
        expect(formatter.display_width(plain(result))).to be <= width
      end
    end
  end
end
