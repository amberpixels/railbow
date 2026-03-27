# frozen_string_literal: true

require "railbow/name_formatter"

RSpec.describe Railbow::NameFormatter do
  describe ".format" do
    # --- Pattern tokens ---

    it "F = first initial" do
      expect(described_class.format("John Doe", "F")).to eq("J")
    end

    it "FF = first 2 chars of first name" do
      expect(described_class.format("John Doe", "FF")).to eq("Jo")
    end

    it "FFF = first 3 chars of first name" do
      expect(described_class.format("John Doe", "FFF")).to eq("Joh")
    end

    it "FFFF+ = full first name" do
      expect(described_class.format("John Doe", "FFFF")).to eq("John")
      expect(described_class.format("John Doe", "FFFFF")).to eq("John")
    end

    it "L = last initial" do
      expect(described_class.format("John Doe", "L")).to eq("D")
    end

    it "LL = first 2 chars of last name" do
      expect(described_class.format("John Doe", "LL")).to eq("Do")
    end

    it "LLLL+ = full last name" do
      expect(described_class.format("John Doe", "LLLL")).to eq("Doe")
    end

    it "M = middle initial" do
      expect(described_class.format("John Michael Doe", "M")).to eq("M")
    end

    it "MMMM = full middle name" do
      expect(described_class.format("John Michael Doe", "MMMM")).to eq("Michael")
    end

    it "multiple middle names" do
      expect(described_class.format("John Michael James Doe", "M")).to eq("M J")
      expect(described_class.format("John Michael James Doe", "MMMM")).to eq("Michael James")
    end

    # --- Literals ---

    it "preserves literal characters" do
      expect(described_class.format("John Doe", "LLLL, FFFF")).to eq("Doe, John")
      expect(described_class.format("John Doe", "FFFF L.")).to eq("John D.")
    end

    # --- Composite patterns ---

    it "FF L pattern" do
      expect(described_class.format("John Doe", "FF L")).to eq("Jo D")
    end

    it "F L pattern" do
      expect(described_class.format("John Doe", "F L")).to eq("J D")
    end

    it "FFFF MMMM LLLL pattern" do
      expect(described_class.format("John Michael Doe", "FFFF MMMM LLLL")).to eq("John Michael Doe")
    end

    # --- Named presets ---

    it "preset: initials" do
      expect(described_class.format("John Doe", "initials")).to eq("J D")
    end

    it "preset: short" do
      expect(described_class.format("John Doe", "short")).to eq("Jo D")
    end

    it "preset: first_name" do
      expect(described_class.format("John Doe", "first_name")).to eq("John")
    end

    it "preset: last_name" do
      expect(described_class.format("John Doe", "last_name")).to eq("Doe")
    end

    it "preset: full_name" do
      expect(described_class.format("John Doe", "full_name")).to eq("John Doe")
      expect(described_class.format("John Michael Doe", "full_name")).to eq("John Michael Doe")
    end

    it "preset: full_name_short" do
      expect(described_class.format("John Doe", "full_name_short")).to eq("John D.")
      expect(described_class.format("John Michael Doe", "full_name_short")).to eq("John D.")
    end

    # --- Edge cases ---

    it "returns empty string for nil" do
      expect(described_class.format(nil, "FF L")).to eq("")
    end

    it "returns empty string for empty string" do
      expect(described_class.format("", "FF L")).to eq("")
    end

    it "single-word name uses it as first name, no last" do
      expect(described_class.format("alice", "FF L")).to eq("Al")
      expect(described_class.format("alice", "FFFF")).to eq("alice")
      expect(described_class.format("alice", "initials")).to eq("A")
    end

    it "no middle name collapses extra spaces" do
      expect(described_class.format("John Doe", "FFFF MMMM LLLL")).to eq("John Doe")
    end

    it "handles name with separators (dots, hyphens, underscores)" do
      expect(described_class.format("Mary-Jane Watson", "FF L")).to eq("Ma W")
      expect(described_class.format("J.R.R. Tolkien", "F LLLL")).to eq("J Tolkien")
    end

    it "short first name with long pattern" do
      expect(described_class.format("Al Smith", "FFF L")).to eq("Al S")
    end

    it "name shorter than token length doesn't crash" do
      expect(described_class.format("Li Wang", "FFF L")).to eq("Li W")
      expect(described_class.format("Li Wang", "FFF LLL")).to eq("Li Wan")
      expect(described_class.format("A B", "FF LL")).to eq("A B")
    end
  end
end
