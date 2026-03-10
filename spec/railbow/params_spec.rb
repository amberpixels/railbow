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
    ENV.delete("RBW_DATE")
    ENV.delete("RBW_CALENDAR")
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

    it "collects repeated keys into arrays" do
      result = described_class.parse_compound("hide:date,hide:author")
      expect(result).to eq("hide" => ["date", "author"])
    end

    it "promotes single key to array on second occurrence" do
      result = described_class.parse_compound("hide:date,diff,hide:author")
      expect(result).to eq("hide" => ["date", "author"], "diff" => true)
    end

    it "collects three repeated keys into array" do
      result = described_class.parse_compound("hide:a,hide:b,hide:c")
      expect(result).to eq("hide" => ["a", "b", "c"])
    end

    it "keeps single keys as scalars" do
      result = described_class.parse_compound("oneline,maxw:80")
      expect(result).to eq("oneline" => true, "maxw" => "80")
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
    it "defaults to '70d' from config" do
      expect(described_class.since).to eq("70d")
    end

    it "can be set to 'all' via ENV override" do
      ENV["RBW_SINCE"] = "all"
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
    it "defaults git_author to 'me'" do
      expect(described_class.git_author).to eq("me")
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

  describe ".extract_branch_ticket" do
    {
      "ws-123" => "ws-123",
      "123" => "123",
      "123-some-feature" => "123",
      "abc123" => "abc123",
      "123/some-feature" => "123",
      "feat/123-some-feature" => "123",
      "ab-123-456/some-feature" => "ab-123-456",
      "feat/ws-1234" => "ws-1234",
      "fix/ABC-42-login-bug" => "ABC-42",
      "hotfix/99-urgent" => "99"
    }.each do |branch, expected|
      it "extracts #{expected.inspect} from #{branch.inspect}" do
        expect(described_class.extract_branch_ticket(branch)).to eq(expected)
      end
    end

    it "returns the original branch name when no ticket pattern matches" do
      expect(described_class.extract_branch_ticket("main")).to eq("main")
    end
  end

  describe ".date_format" do
    it "defaults to 'full'" do
      expect(described_class.date_format).to eq("full")
    end

    it "reads RBW_DATE=rel" do
      ENV["RBW_DATE"] = "rel"
      expect(described_class.date_format).to eq("rel")
    end

    it "reads RBW_DATE=short" do
      ENV["RBW_DATE"] = "short"
      expect(described_class.date_format).to eq("short")
    end

    it "reads RBW_DATE=custom(%b %d)" do
      ENV["RBW_DATE"] = "custom(%b %d)"
      expect(described_class.date_format).to eq("custom(%b %d)")
    end

    it "returns unknown values as-is" do
      ENV["RBW_DATE"] = "custom(%b %d, %Y)"
      expect(described_class.date_format).to eq("custom(%b %d, %Y)")
    end
  end

  describe "view compound accessors" do
    it "defaults all view options to true" do
      expect(described_class.view_calendar?).to be true
      expect(described_class.view_tables?).to be true
    end

    it "parses calendar" do
      ENV["RBW_VIEW"] = "calendar"

      expect(described_class.view_calendar?).to be true
    end

    it "parses tables" do
      ENV["RBW_VIEW"] = "tables"

      expect(described_class.view_tables?).to be true
    end

    it "parses combined view options" do
      ENV["RBW_VIEW"] = "calendar,tables"

      expect(described_class.view_calendar?).to be true
      expect(described_class.view_tables?).to be true
    end

    it "warns about deprecated tables:nowrap" do
      ENV["RBW_VIEW"] = "tables:nowrap"

      expect { described_class.view_tables? }
        .to output(/deprecated.*RBW_COMPACT=oneline/).to_stderr
    end
  end

  describe "calendar compound accessors" do
    it "defaults calendar_wticks? to true" do
      expect(described_class.calendar_wticks?).to be true
    end

    it "enables wticks with RBW_CALENDAR=wticks" do
      ENV["RBW_VIEW"] = "calendar"
      ENV["RBW_CALENDAR"] = "wticks"
      expect(described_class.calendar_wticks?).to be true
    end

    it "requires calendar mode for wticks" do
      ENV["RBW_VIEW"] = "tables"
      ENV["RBW_CALENDAR"] = "wticks"
      expect(described_class.calendar_wticks?).to be false
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

  describe "compact compound accessors" do
    it "returns empty hash by default" do
      expect(described_class.compact).to eq({})
    end

    it "parses oneline" do
      ENV["RBW_COMPACT"] = "oneline"
      expect(described_class.compact_oneline?).to be true
    end

    it "parses strip-format" do
      ENV["RBW_COMPACT"] = "strip-format"
      expect(described_class.compact_strip_format?).to be true
    end

    it "parses dense" do
      ENV["RBW_COMPACT"] = "dense"
      expect(described_class.compact_dense?).to be true
    end

    it "parses noheader" do
      ENV["RBW_COMPACT"] = "noheader"
      expect(described_class.compact_noheader?).to be true
    end

    it "parses maxw as integer" do
      ENV["RBW_COMPACT"] = "maxw:80"
      expect(described_class.compact_maxw).to eq(80)
    end

    it "returns nil maxw when unset" do
      expect(described_class.compact_maxw).to be_nil
    end

    it "parses single hidden column" do
      ENV["RBW_COMPACT"] = "hide:date"
      expect(described_class.compact_hidden_columns).to eq(["date"])
    end

    it "parses multiple hidden columns via repeated keys" do
      ENV["RBW_COMPACT"] = "hide:date,hide:author"
      expect(described_class.compact_hidden_columns).to eq(["date", "author"])
    end

    it "returns empty array for hidden_columns when unset" do
      expect(described_class.compact_hidden_columns).to eq([])
    end

    it "builds compact_options hash" do
      ENV["RBW_COMPACT"] = "oneline,dense,maxw:60,hide:date"
      opts = described_class.compact_options
      expect(opts[:oneline]).to be true
      expect(opts[:dense]).to be true
      expect(opts[:maxw]).to eq(60)
      expect(opts[:hidden_columns]).to eq(["date"])
      expect(opts[:noheader]).to be false
    end

    it "defaults all compact options to off" do
      opts = described_class.compact_options
      expect(opts[:oneline]).to be false
      expect(opts[:dense]).to be false
      expect(opts[:noheader]).to be false
      expect(opts[:maxw]).to be_nil
      expect(opts[:hidden_columns]).to eq([])
    end
  end
end
