# frozen_string_literal: true

require "railbow/name_collision_resolver"

RSpec.describe Railbow::NameCollisionResolver do
  describe ".resolve" do
    it "returns plain formatting when no collisions" do
      result = described_class.resolve(["John Doe", "Jane Smith"], "F L")
      expect(result).to eq("John Doe" => "J D", "Jane Smith" => "J S")
    end

    it "matches NameFormatter output when no collisions" do
      names = ["Bruce Wayne", "Clark Kent"]
      result = described_class.resolve(names, "FF L")
      names.each do |n|
        expect(result[n]).to eq(Railbow::NameFormatter.format(n, "FF L"))
      end
    end

    it "expands F to resolve first-name collision" do
      result = described_class.resolve(["John Doe", "Jane Doe"], "F L")
      expect(result["John Doe"]).to eq("Jo D")
      expect(result["Jane Doe"]).to eq("Ja D")
    end

    it "expands F multiple times when needed" do
      result = described_class.resolve(["John Doe", "Joseph Doe"], "F L")
      expect(result["John Doe"]).to eq("Joh D")
      expect(result["Joseph Doe"]).to eq("Jos D")
    end

    it "expands L when F is too short to disambiguate" do
      result = described_class.resolve(["Al Davis", "Al Daniels"], "F L")
      expect(result["Al Davis"]).not_to eq(result["Al Daniels"])
      expect(result["Al Davis"]).to start_with("Al ")
      expect(result["Al Daniels"]).to start_with("Al ")
    end

    it "resolves single-word name collisions via F expansion" do
      result = described_class.resolve(["alice", "alex"], "F L")
      expect(result["alice"]).not_to eq(result["alex"])
    end

    it "works with preset names" do
      result = described_class.resolve(["John Doe", "Jane Doe"], "initials")
      expect(result["John Doe"]).not_to eq(result["Jane Doe"])
    end

    it "works with short preset" do
      result = described_class.resolve(["John Doe", "Jane Doe"], "short")
      expect(result["John Doe"]).to eq("Jo D")
      expect(result["Jane Doe"]).to eq("Ja D")
    end

    it "only expands colliding names, leaves others unchanged" do
      result = described_class.resolve(["John Doe", "Jane Doe", "Bob Smith"], "F L")
      expect(result["Bob Smith"]).to eq("B S")
      expect(result["John Doe"]).not_to eq(result["Jane Doe"])
    end

    it "deduplicates identical raw names" do
      result = described_class.resolve(["John Doe", "John Doe"], "F L")
      expect(result["John Doe"]).to eq("J D")
      expect(result.size).to eq(1)
    end

    it "handles nil and empty names in input" do
      result = described_class.resolve([nil, "", "John Doe"], "F L")
      expect(result["John Doe"]).to eq("J D")
      expect(result).not_to have_key(nil)
      expect(result).not_to have_key("")
    end

    it "handles empty input list" do
      expect(described_class.resolve([], "F L")).to eq({})
    end

    it "handles single name" do
      result = described_class.resolve(["John Doe"], "F L")
      expect(result["John Doe"]).to eq("J D")
    end

    it "resolves 3-way collision" do
      result = described_class.resolve(
        ["John Doe", "Jane Doe", "James Doe"], "F L"
      )
      values = result.values
      expect(values.uniq.size).to eq(3), "expected 3 unique names, got: #{values}"
    end

    it "resolves 5-way collision" do
      names = ["John Doe", "Jane Doe", "James Doe", "Jacob Doe", "Jason Doe"]
      result = described_class.resolve(names, "F L")
      values = result.values
      expect(values.uniq.size).to eq(5), "expected 5 unique names, got: #{values}"
    end

    it "only expands names that still collide, keeps others minimal" do
      # All three are "J D"; Jamie parts at FF, John and Joseph only at FFF.
      result = described_class.resolve(
        ["John Doe", "Joseph Doe", "Jamie Doe"], "F L"
      )
      expect(result["Jamie Doe"]).to eq("Ja D")
      expect(result["John Doe"]).to eq("Joh D")
      expect(result["Joseph Doe"]).to eq("Jos D")
      expect(result["Jamie Doe"].length).to be < result["John Doe"].length
    end

    it "stops expansion as soon as a name becomes unique" do
      result = described_class.resolve(
        ["John Doe", "Jane Doe", "Jake Smith"], "F L"
      )
      expect(result["Jake Smith"]).to eq("J S")
      expect(result["John Doe"]).to eq("Jo D")
      expect(result["Jane Doe"]).to eq("Ja D")
    end

    it "does not over-expand when expansion would collide with a different group" do
      # Bruce Banner and Barry Brown part at "Br B" / "Ba B". Brian Blake may
      # format to "Br B" too, which must not send Bruce Banner further.
      result = described_class.resolve(
        ["Bruce Banner", "Barry Brown", "Brian Blake"], "F L"
      )
      expect(result["Bruce Banner"].length).to be < "Bruce Banner".length
    end

    it "merges names that differ only in middle name" do
      result = described_class.resolve(
        ["Tony Stark", "Tony Edward Stark"], "FF L"
      )
      expect(result["Tony Stark"]).to eq("To S")
      expect(result["Tony Edward Stark"]).to eq("To S")
    end

    it "merges same-person names and still resolves real collisions" do
      result = described_class.resolve(
        ["Tony Stark", "Tony Edward Stark", "Thor Odinson"], "F L"
      )
      expect(result["Tony Stark"]).to eq(result["Tony Edward Stark"])
      expect(result["Thor Odinson"]).not_to eq(result["Tony Stark"])
    end

    it "handles case-insensitive first+last matching for merging" do
      result = described_class.resolve(
        ["loki", "Loki"], "FF L"
      )
      expect(result["loki"]).to eq(result["Loki"])
    end

    it "handles already-expanded pattern with collision" do
      result = described_class.resolve(["John Doe", "John Daniels"], "FFFF L")
      expect(result["John Doe"]).not_to eq(result["John Daniels"])
    end
  end
end
