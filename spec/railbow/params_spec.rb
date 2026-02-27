# frozen_string_literal: true

require "spec_helper"
require "railbow/params"

RSpec.describe Railbow::Params do
  before do
    ENV.delete("RBW_HELP")
    ENV.delete("RBW_PLAIN")
    ENV.delete("RBW_SINCE")
    ENV.delete("RBW_SORT")
    ENV.delete("RBW_COMPACT")
    ENV.delete("RBW_VERB")
    ENV.delete("RBW_GIT")
    ENV.delete("RBW_VIEW")
  end

  describe ".parse_compound" do
    it "parses bare tokens as boolean true" do
      result = described_class.parse_compound("diff")
      expect(result).to eq("diff" => true)
    end

    it "parses key:value tokens" do
      result = described_class.parse_compound("author:me")
      expect(result).to eq("author" => "me")
    end

    it "parses comma-separated mixed tokens" do
      result = described_class.parse_compound("author:me,diff,base:develop")
      expect(result).to eq("author" => "me", "diff" => true, "base" => "develop")
    end

    it "splits on first colon only (preserves regex colons)" do
      result = described_class.parse_compound("mask:(WS-[^/]+)/")
      expect(result).to eq("mask" => "(WS-[^/]+)/")
    end

    it "returns empty hash for nil" do
      expect(described_class.parse_compound(nil)).to eq({})
    end

    it "returns empty hash for blank string" do
      expect(described_class.parse_compound("  ")).to eq({})
    end
  end

  describe ".truthy?" do
    %w[1 true yes on].each do |val|
      it "returns true for #{val.inspect}" do
        expect(described_class.truthy?(val)).to be true
      end
    end

    %w[0 false no off].each do |val|
      it "returns false for #{val.inspect}" do
        expect(described_class.truthy?(val)).to be false
      end
    end

    it "returns false for nil" do
      expect(described_class.truthy?(nil)).to be false
    end
  end

  describe ".parse_since" do
    it "returns nil for 'all'" do
      expect(described_class.parse_since("all")).to be_nil
    end

    it "returns nil for nil" do
      expect(described_class.parse_since(nil)).to be_nil
    end

    it "parses days" do
      expect(described_class.parse_since("30d")).to eq(Date.today - 30)
    end

    it "parses weeks" do
      expect(described_class.parse_since("2w")).to eq(Date.today - 14)
    end

    it "parses months" do
      expect(described_class.parse_since("2mo")).to eq(Date.today.prev_month(2))
    end

    it "parses years" do
      expect(described_class.parse_since("1y")).to eq(Date.today.prev_year(1))
    end

    it "warns and returns nil for unrecognized values" do
      expect { described_class.parse_since("bogus", context: "test") }
        .to output(/Warning.*RBW_SINCE=bogus/).to_stderr
    end
  end

  describe ".help?" do
    it "returns false by default" do
      expect(described_class.help?).to be false
    end

    it "returns true when RBW_HELP=1" do
      ENV["RBW_HELP"] = "1"
      expect(described_class.help?).to be true
    end
  end

  describe ".since" do
    it "defaults to 'all'" do
      expect(described_class.since).to eq("all")
    end

    it "reads RBW_SINCE" do
      ENV["RBW_SINCE"] = "2mo"
      expect(described_class.since).to eq("2mo")
    end
  end

  describe ".sort" do
    it "defaults to 'file'" do
      expect(described_class.sort).to eq("file")
    end

    it "reads RBW_SORT" do
      ENV["RBW_SORT"] = "date"
      expect(described_class.sort).to eq("date")
    end
  end

  describe "git compound accessors" do
    it "defaults git_author to 'off'" do
      expect(described_class.git_author).to eq("off")
    end

    it "bare 'author' defaults to 'all'" do
      ENV["RBW_GIT"] = "author"

      expect(described_class.git_author).to eq("all")
    end

    it "parses author:me" do
      ENV["RBW_GIT"] = "author:me"

      expect(described_class.git_author).to eq("me")
    end

    it "parses diff" do
      ENV["RBW_GIT"] = "diff"

      expect(described_class.git_diff?).to be true
    end

    it "parses base:develop" do
      ENV["RBW_GIT"] = "base:develop"

      expect(described_class.git_base).to eq("develop")
    end

    it "parses mask with regex" do
      ENV["RBW_GIT"] = "mask:(WS-[^/]+)/"

      expect(described_class.git_mask).to eq("(WS-[^/]+)/")
    end

    it "parses combined git options" do
      ENV["RBW_GIT"] = "author:me,diff,base:develop"

      expect(described_class.git_author).to eq("me")
      expect(described_class.git_diff?).to be true
      expect(described_class.git_base).to eq("develop")
    end
  end

  describe "view compound accessors" do
    it "defaults all view options to false" do
      expect(described_class.view_calendar?).to be false
      expect(described_class.view_ago?).to be false
      expect(described_class.view_tables?).to be false
      expect(described_class.view_tables_nowrap?).to be false
    end

    it "parses calendar" do
      ENV["RBW_VIEW"] = "calendar"

      expect(described_class.view_calendar?).to be true
    end

    it "parses ago" do
      ENV["RBW_VIEW"] = "ago"

      expect(described_class.view_ago?).to be true
    end

    it "parses tables" do
      ENV["RBW_VIEW"] = "tables"

      expect(described_class.view_tables?).to be true
    end

    it "parses tables:nowrap" do
      ENV["RBW_VIEW"] = "tables:nowrap"

      expect(described_class.view_tables?).to be true
      expect(described_class.view_tables_nowrap?).to be true
    end

    it "parses tables,nowrap as fallback" do
      ENV["RBW_VIEW"] = "tables,nowrap"

      expect(described_class.view_tables?).to be true
      expect(described_class.view_tables_nowrap?).to be true
    end

    it "parses combined view options" do
      ENV["RBW_VIEW"] = "calendar,ago,tables"

      expect(described_class.view_calendar?).to be true
      expect(described_class.view_ago?).to be true
      expect(described_class.view_tables?).to be true
    end
  end

  describe ".verb" do
    it "returns nil by default" do
      expect(described_class.verb).to be_nil
    end

    it "reads RBW_VERB" do
      ENV["RBW_VERB"] = "GET"
      expect(described_class.verb).to eq("GET")
    end
  end

  describe ".compact" do
    it "returns nil by default" do
      expect(described_class.compact).to be_nil
    end

    it "reads RBW_COMPACT" do
      ENV["RBW_COMPACT"] = "0"
      expect(described_class.compact).to eq("0")
    end
  end
end
