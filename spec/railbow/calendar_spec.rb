# frozen_string_literal: true

require "spec_helper"
require "railbow/calendar"

RSpec.describe Railbow::Calendar do
  # 2026-05-29 Fri W22 | 06-01 Mon W23 | 06-03 Wed W23 | 06-08 Mon W24 | 07-01 Wed W27
  let(:versions) do
    %w[
      20260529090000
      20260601090000
      20260603090000
      20260608090000
      20260701090000
    ]
  end

  describe ".none" do
    it "is empty furniture" do
      furniture = described_class.none

      expect(furniture.separators).to be_empty
      expect(furniture.tick_rows).to be_empty
    end
  end

  describe ".build" do
    it "separates months and nothing else by default" do
      furniture = described_class.build(versions)

      expect(furniture.separators).to eq({1 => "Jun 2026   W23", 4 => "Jul 2026   W27"})
      expect(furniture.tick_rows).to be_empty
    end

    it "adds no separator when every migration shares a month" do
      expect(described_class.build(versions.first(1)).separators).to be_empty
    end

    it "adds a week separator per ISO week when weeks are on" do
      furniture = described_class.build(versions, weeks: true)

      expect(furniture.separators).to eq({
        1 => "Jun 2026   W23",
        3 => "Jun 2026   W24",
        4 => "Jul 2026   W27"
      })
    end

    it "gives week rows the month prefix too, so week numbers line up" do
      labels = described_class.build(versions, weeks: true).separators.values

      expect(labels).to all(match(/\A\w{3} \d{4}   W\d{2}\z/))
    end

    it "lets a month boundary stand in for the week boundary it also is" do
      # Index 1 opens both June and W23, and gets one row rather than two
      with_weeks = described_class.build(versions, weeks: true).separators
      without_weeks = described_class.build(versions).separators

      expect(with_weeks[1]).to eq("Jun 2026   W23")
      expect(with_weeks.keys - without_weeks.keys).to eq([3]) # only the mid-month week
    end

    it "marks week openings as ticks independently of week separators" do
      furniture = described_class.build(versions, ticks: true)

      expect(furniture.tick_rows.to_a).to eq([1, 3, 4])
      expect(furniture.separators.keys).to eq([1, 4]) # months only
    end

    it "counts the migrations each separator introduces" do
      furniture = described_class.build(versions, weeks: true, counts: true)

      # W23 covers rows 1-2, W24 covers row 3, W27 covers row 4
      expect(furniture.separators).to eq({
        1 => "Jun 2026   W23 · 2 migrations",
        3 => "Jun 2026   W24 · 1 migration",
        4 => "Jul 2026   W27 · 1 migration"
      })
    end

    it "honors custom month and week labels" do
      furniture = described_class.build(versions, weeks: true, month_label: "%Y-%m", week_label: "week %V")

      expect(furniture.separators[1]).to eq("2026-06")
      expect(furniture.separators[3]).to eq("week 24")
    end

    it "ignores versions it cannot read as a date" do
      furniture = described_class.build(["not-a-version", "20260601090000", "20260701090000"], ticks: true)

      expect(furniture.separators).to eq({2 => "Jul 2026   W27"})
      expect(furniture.tick_rows.to_a).to eq([2])
    end

    it "treats the same week number in different ISO years as a boundary" do
      # 2025-12-29 is W01 of 2026; a year later 2026-12-28 is W53 of 2026
      furniture = described_class.build(%w[20251229090000 20261228090000], weeks: true, ticks: true)

      expect(furniture.tick_rows.to_a).to eq([1])
    end
  end
end
