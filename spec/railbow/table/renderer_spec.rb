# frozen_string_literal: true

require "spec_helper"
require "railbow/table"

RSpec.describe Railbow::Table::Renderer do
  def strip_ansi(str)
    str.to_s.gsub(/\e\[[0-9;]*m/, "")
  end

  describe "WALLS theme" do
    let(:columns) do
      [
        Railbow::Table::Column.new(label: "Status"),
        Railbow::Table::Column.new(label: "ID"),
        Railbow::Table::Column.new(label: "Name")
      ]
    end

    let(:renderer) do
      described_class.new(columns: columns, theme: Railbow::Table::Themes::WALLS)
    end

    it "renders header and data rows" do
      rows = [["up", "001", "CreateUsers"], ["down", "002", "AddPosts"]]
      result = renderer.render(rows)
      lines = result.split("\n")

      expect(lines.size).to eq(3)
      expect(strip_ansi(lines[0])).to include("Status")
      expect(strip_ansi(lines[0])).to include("ID")
      expect(strip_ansi(lines[0])).to include("Name")
      expect(strip_ansi(lines[1])).to include("up")
      expect(strip_ansi(lines[1])).to include("001")
      expect(strip_ansi(lines[2])).to include("down")
    end

    it "uses │ column separators in data rows" do
      rows = [["up", "001", "Test"]]
      result = renderer.render(rows)
      data_line = result.split("\n")[1]
      expect(data_line).to include("\u2502")
    end

    it "uses space separators in header" do
      rows = [["up", "001", "Test"]]
      result = renderer.render(rows)
      header_line = result.split("\n")[0]
      # Header should NOT contain │
      expect(strip_ansi(header_line)).not_to include("\u2502")
    end

    it "pads cells with spaces on each side" do
      rows = [["up", "001", "Test"]]
      result = renderer.render(rows)
      data_line = result.split("\n")[1]
      # Cells should have space padding around them
      expect(data_line).to match(/\s+up\s+/)
    end

    it "applies RESET before each separator to prevent ANSI leaking" do
      rows = [["\e[32mup\e[0m", "001", "Test"]]
      result = renderer.render(rows)
      data_line = result.split("\n")[1]
      # Before each │, there should be a RESET
      segments = data_line.split("\u2502")
      segments[0...-1].each do |seg|
        expect(seg).to end_with("\e[0m ")
      end
    end
  end

  describe "PLAIN theme" do
    let(:columns) do
      [
        Railbow::Table::Column.new(label: "Verb"),
        Railbow::Table::Column.new(label: "URI Pattern"),
        Railbow::Table::Column.new(label: "Controller#Action"),
        Railbow::Table::Column.new(label: "Prefix")
      ]
    end

    let(:renderer) do
      described_class.new(columns: columns, theme: Railbow::Table::Themes::PLAIN)
    end

    it "renders without wall separators" do
      rows = [["GET", "/users", "users#index", "users"]]
      result = renderer.render(rows)
      expect(result).not_to include("\u2502")
    end

    it "aligns columns with space separators" do
      rows = [
        ["GET", "/users", "users#index", "users"],
        ["DELETE", "/users/:id", "users#destroy", ""]
      ]
      result = renderer.render(rows)
      plain = strip_ansi(result)
      lines = plain.split("\n")

      # Header and data lines should have aligned columns
      expect(lines.size).to eq(3)
    end

    it "applies bold formatting to header cells" do
      rows = [["GET", "/users", "users#index", "users"]]
      result = renderer.render(rows)
      header = result.split("\n")[0]
      expect(header).to include("\e[1m")
    end
  end

  describe "column alignment" do
    it "pads columns to the widest content" do
      columns = [
        Railbow::Table::Column.new(label: "Col1"),
        Railbow::Table::Column.new(label: "Col2")
      ]
      renderer = described_class.new(columns: columns, theme: Railbow::Table::Themes::PLAIN)
      rows = [["ab", "val1"], ["abcdefghij", "val2"]]
      result = strip_ansi(renderer.render(rows))
      lines = result.split("\n")

      # Data rows should have aligned second column
      data_lines = lines[1..]
      positions = data_lines.map { |l| l.index("val") }
      expect(positions.compact.uniq.size).to eq(1)
    end
  end

  describe "truncation" do
    it "truncates cells when column has truncate and max_width" do
      columns = [
        Railbow::Table::Column.new(label: "Name", max_width: 10, truncate: true),
        Railbow::Table::Column.new(label: "Val")
      ]
      renderer = described_class.new(columns: columns, theme: Railbow::Table::Themes::WALLS)
      rows = [["A very long name that exceeds", "ok"]]
      result = strip_ansi(renderer.render(rows))
      data_line = result.split("\n")[1]
      expect(data_line).to include("...")
    end

    it "does not truncate when content fits" do
      columns = [
        Railbow::Table::Column.new(label: "Name", max_width: 50, truncate: true),
        Railbow::Table::Column.new(label: "Val")
      ]
      renderer = described_class.new(columns: columns, theme: Railbow::Table::Themes::WALLS)
      rows = [["short", "ok"]]
      result = strip_ansi(renderer.render(rows))
      expect(result).not_to include("...")
    end
  end

  describe "separators" do
    it "inserts separator lines between rows" do
      columns = [
        Railbow::Table::Column.new(label: "Name"),
        Railbow::Table::Column.new(label: "Val")
      ]
      renderer = described_class.new(columns: columns, theme: Railbow::Table::Themes::WALLS)
      rows = [["a", "1"], ["b", "2"], ["c", "3"]]
      result = renderer.render(rows, separators: {1 => "Mar 2023"})
      lines = result.split("\n")

      expect(lines.size).to eq(5) # header + separator + 3 rows
      expect(strip_ansi(lines[2])).to include("Mar 2023")
    end

    it "does not insert separator for PLAIN theme (no format_separator)" do
      columns = [
        Railbow::Table::Column.new(label: "Name"),
        Railbow::Table::Column.new(label: "Val")
      ]
      renderer = described_class.new(columns: columns, theme: Railbow::Table::Themes::PLAIN)
      rows = [["a", "1"], ["b", "2"]]
      result = renderer.render(rows, separators: {1 => "Mar 2023"})
      lines = result.split("\n")
      expect(lines.size).to eq(3) # header + 2 rows, no separator
    end
  end

  describe "highlight_rows" do
    it "wraps highlighted rows in WHITE" do
      columns = [
        Railbow::Table::Column.new(label: "Name"),
        Railbow::Table::Column.new(label: "Val")
      ]
      renderer = described_class.new(columns: columns, theme: Railbow::Table::Themes::WALLS)
      rows = [["a", "1"], ["b", "2"]]
      result = renderer.render(rows, highlight_rows: Set[0])
      lines = result.split("\n")

      # Highlighted row should start with WHITE
      expect(lines[1]).to start_with("\e[97m")
      # Non-highlighted row should not
      expect(lines[2]).not_to start_with("\e[97m")
    end
  end

  describe "terminal-width wrapping of last column" do
    it "wraps the last column within its column space (PLAIN)" do
      columns = [
        Railbow::Table::Column.new(label: "Verb"),
        Railbow::Table::Column.new(label: "Path"),
        Railbow::Table::Column.new(label: "Prefix")
      ]
      renderer = described_class.new(columns: columns, theme: Railbow::Table::Themes::PLAIN)
      allow(renderer).to receive(:terminal_width).and_return(40)

      rows = [["GET", "/short", "long prefix name overflows terminal"]]
      result = renderer.render(rows)
      data_lines = result.split("\n")[1..] # skip header

      # Should wrap to multiple lines, not truncate
      expect(data_lines.size).to be > 1
      # Full content should be present across all lines
      full_plain = strip_ansi(data_lines.join(" "))
      expect(full_plain).to include("overflows")
      expect(full_plain).to include("terminal")
    end

    it "wraps last column with blank prefix for preceding columns (WALLS)" do
      columns = [
        Railbow::Table::Column.new(label: "ID"),
        Railbow::Table::Column.new(label: "Details")
      ]
      renderer = described_class.new(
        columns: columns,
        theme: Railbow::Table::Themes::WALLS
      )
      allow(renderer).to receive(:terminal_width).and_return(30)

      long_text = "word " * 20
      rows = [["1", long_text.strip]]
      result = renderer.render(rows)
      data_lines = result.split("\n")[1..] # skip header

      expect(data_lines.size).to be > 1
    end

    it "wraps underscore-separated tokens at underscore boundaries" do
      columns = [
        Railbow::Table::Column.new(label: "Verb"),
        Railbow::Table::Column.new(label: "Prefix")
      ]
      renderer = described_class.new(columns: columns, theme: Railbow::Table::Themes::PLAIN)
      allow(renderer).to receive(:terminal_width).and_return(40)

      long_prefix = "parent_portal_verify_insurance_information"
      rows = [["GET", long_prefix]]
      result = renderer.render(rows)
      data_lines = result.split("\n")[1..]

      expect(data_lines.size).to be > 1
      # Full content preserved across lines
      full_plain = strip_ansi(data_lines.join)
      expect(full_plain.gsub(/\s+/, "")).to include(long_prefix.gsub(/\s+/, ""))
    end

    it "does not wrap when row fits in terminal" do
      columns = [
        Railbow::Table::Column.new(label: "A"),
        Railbow::Table::Column.new(label: "B")
      ]
      renderer = described_class.new(columns: columns, theme: Railbow::Table::Themes::PLAIN)
      allow(renderer).to receive(:terminal_width).and_return(200)

      rows = [["short", "value"]]
      result = renderer.render(rows)
      data_lines = result.split("\n")[1..]
      expect(data_lines.size).to eq(1)
    end
  end

  describe "ANSI-colored content" do
    it "correctly measures width ignoring ANSI codes" do
      columns = [
        Railbow::Table::Column.new(label: "Status"),
        Railbow::Table::Column.new(label: "Name")
      ]
      renderer = described_class.new(columns: columns, theme: Railbow::Table::Themes::WALLS)
      rows = [["\e[32mup\e[0m", "test"], ["down", "other"]]
      result = renderer.render(rows)
      plain = strip_ansi(result)
      lines = plain.split("\n")

      # Both rows should have the same column widths
      name_pos_1 = lines[1].index("test")
      name_pos_2 = lines[2].index("other")
      expect(name_pos_1).to eq(name_pos_2)
    end
  end

  describe "empty input" do
    it "returns empty string with no columns" do
      renderer = described_class.new(columns: [], theme: Railbow::Table::Themes::PLAIN)
      expect(renderer.render([])).to eq("")
    end

    it "renders only header with no rows" do
      columns = [Railbow::Table::Column.new(label: "Name")]
      renderer = described_class.new(columns: columns, theme: Railbow::Table::Themes::PLAIN)
      result = renderer.render([])
      lines = result.split("\n")
      expect(lines.size).to eq(1)
      expect(strip_ansi(lines[0])).to include("Name")
    end
  end

  describe "min_width and max_width" do
    it "respects min_width even when content is shorter" do
      columns = [
        Railbow::Table::Column.new(label: "A", min_width: 20),
        Railbow::Table::Column.new(label: "B")
      ]
      renderer = described_class.new(columns: columns, theme: Railbow::Table::Themes::PLAIN)
      rows = [["x", "y"]]
      result = strip_ansi(renderer.render(rows))
      lines = result.split("\n")

      # The B column should be at position >= 20
      b_pos = lines[1].index("y")
      expect(b_pos).to be >= 20
    end

    it "respects max_width clamping" do
      columns = [
        Railbow::Table::Column.new(label: "A", max_width: 5),
        Railbow::Table::Column.new(label: "B")
      ]
      renderer = described_class.new(columns: columns, theme: Railbow::Table::Themes::PLAIN)
      rows = [["very long content", "y"]]
      result = strip_ansi(renderer.render(rows))
      lines = result.split("\n")

      # The B column should be near position 5, not far out
      b_pos = lines[1].index("y")
      expect(b_pos).to be <= 10
    end
  end
end
