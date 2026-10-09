# frozen_string_literal: true

require "spec_helper"
require "railbow/clock"

RSpec.describe Railbow::Clock do
  # 08:43:29 UTC, which is 10:43 in Budapest (CEST) and 04:43 in New York (EDT).
  let(:version) { "20261008084329" }

  around do |example|
    ENV["TZ"] = "Europe/Budapest"
    example.run
  ensure
    ENV["TZ"] = "UTC"
  end

  def with_tz(name)
    allow(Railbow::Params).to receive(:tz).and_return(name)
  end

  def hhmm(time)
    time.strftime("%Y-%m-%d %H:%M")
  end

  describe ".from_version" do
    it "reads a migration ID as UTC and shows it on the local clock by default" do
      with_tz("local")

      expect(hhmm(described_class.from_version(version))).to eq("2026-10-08 10:43")
    end

    it "shows UTC when asked" do
      with_tz("utc")

      expect(hhmm(described_class.from_version(version))).to eq("2026-10-08 08:43")
    end

    it "accepts IANA zone names" do
      with_tz("America/New_York")

      expect(hhmm(described_class.from_version(version))).to eq("2026-10-08 04:43")
    end

    it "accepts Rails zone names" do
      with_tz("Eastern Time (US & Canada)")

      expect(hhmm(described_class.from_version(version))).to eq("2026-10-08 04:43")
    end

    it "warns about an unknown zone and falls back to local time" do
      with_tz("Pawshop/Nowhere")

      time = nil
      expect { time = described_class.from_version(version) }
        .to output(/unrecognized RBW_TZ=Pawshop\/Nowhere/).to_stderr
      expect(hhmm(time)).to eq("2026-10-08 10:43")
    end

    it "returns nil for anything that is not a migration ID" do
      expect(described_class.from_version("001")).to be_nil
      expect(described_class.from_version("20261399999999")).to be_nil
    end
  end

  describe ".today" do
    # 23:30 UTC on Oct 8 is already Oct 9 in Budapest.
    before { allow(Time).to receive(:now).and_return(Time.utc(2026, 10, 8, 23, 30)) }

    it "is the date on railbow's clock" do
      with_tz("local")
      expect(described_class.today).to eq(Date.new(2026, 10, 9))

      with_tz("utc")
      expect(described_class.today).to eq(Date.new(2026, 10, 8))
    end
  end

  describe ".version_at" do
    it "is the migration ID of midnight on railbow's clock" do
      with_tz("local")
      expect(described_class.version_at(Date.new(2026, 10, 9))).to eq("20261008220000")

      with_tz("America/New_York")
      expect(described_class.version_at(Date.new(2026, 10, 9))).to eq("20261009040000")
    end
  end

  describe "relative dates" do
    it "measures a migration's age from UTC, whatever the clock" do
      with_tz("local")
      two_hours_ago = (Time.now.utc - (2 * 3600) - 60).strftime("%Y%m%d%H%M%S")

      expect(Railbow::Formatters::Base.new.format_date(two_hours_ago, "rel")).to eq("~2hr ago")
    end
  end
end
