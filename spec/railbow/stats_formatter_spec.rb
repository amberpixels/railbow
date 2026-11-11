# frozen_string_literal: true

require "spec_helper"
require "active_support"
require "active_support/core_ext/class/attribute"
require "rails/code_statistics"
require "railbow/stats_formatter"

RSpec.describe Railbow::StatsFormatter do
  # Rails 8 namespaces both classes under Rails::, Rails 7.2 has them top-level.
  let(:stats_class) { defined?(Rails::CodeStatistics) ? Rails::CodeStatistics : ::CodeStatistics }
  let(:calculator_class) do
    defined?(Rails::CodeStatisticsCalculator) ? Rails::CodeStatisticsCalculator : ::CodeStatisticsCalculator
  end

  # A subclass, so the real CodeStatistics stays untouched for other specs
  # while super still reaches the stock table.
  let(:klass) do
    Class.new(stats_class) do
      prepend Railbow::StatsFormatter

      # Rails 8 keeps test types in a class attribute, Rails 7.2 in a constant.
      if respond_to?(:test_types)
        self.test_types = test_types + ["Model specs"]
      else
        const_set(:TEST_TYPES, superclass::TEST_TYPES + ["Model specs"])
      end
    end
  end

  let(:data) do
    {
      "Controllers" => [57143, 42693, 212, 3472],
      "Models" => [76529, 48353, 302, 4819],
      "Views" => [132781, 128844, 0, 0],
      "Model specs" => [9033, 7072, 0, 64]
    }
  end

  def build(data)
    klass.allocate.tap do |stats|
      stats.instance_variable_set(:@pairs, data.keys.map { |name| [name, "/srv/pawshop"] })
      stats.instance_variable_set(:@statistics, data.transform_values { |v| calculator_class.new(*v) })
      stats.instance_variable_set(:@total, nil)
    end
  end

  def strip_ansi(str)
    str.gsub(/\e\[[0-9;]*m/, "")
  end

  def render(data = self.data)
    result = :unset
    out = strip_ansi(capture_stdout { result = build(data).to_s })
    [out, result]
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  def line_for(output, name)
    output.lines.find { |l| l.strip.start_with?(name) }
  end

  before { allow(Railbow).to receive(:plain?).and_return(false) }

  it "prints the table and returns nil, as stock Rails does" do
    out, result = render

    expect(result).to be_nil
    expect(out).to include("Controllers")
  end

  it "groups code above tests under their own headings" do
    out, = render
    names = out.lines.grep(/│/).map { |l| l.split("│").first.strip }.reject(&:empty?)

    expect(names).to eq(["Code", "Controllers", "Models", "Views", "Tests", "Model specs", "Total"])
  end

  it "groups thousands" do
    expect(line_for(render.first, "Views")).to include("132,781").and include("128,844")
  end

  it "computes ratios with the stock integer math" do
    cells = line_for(render.first, "Controllers").split("│").map(&:strip)

    # 3472 / 212 = 16, 42693 / 3472 - 2 = 10
    expect(cells[5..6]).to eq(%w[16 10])
  end

  it "sums the total row" do
    cells = line_for(render.first, "Total").split("│").map(&:strip)

    expect(cells[1..4]).to eq(["275,486", "226,962", "514", "8,355"])
  end

  it "shows each directory's share of all LOC" do
    out, = render

    expect(line_for(out, "Views")).to include("56.8%")
    expect(line_for(out, "Model specs")).to include("3.1%")
  end

  it "summarizes code against tests" do
    expect(render.first).to include("Code 219,890 LOC").and include("Tests 7,072 LOC")
      .and include("Code to Test Ratio 1:0.0")
  end

  it "leaves the summary ratio out when there is no code" do
    out, = render("Model specs" => [10, 8, 0, 1])

    expect(out).to include("Tests 8 LOC")
    expect(out).not_to include("Ratio")
  end

  it "prints the stock Rails table when plain" do
    allow(Railbow).to receive(:plain?).and_return(true)
    out, = render

    expect(out).to include("| Name")
  end

  it "prints the stock Rails table when rendering fails" do
    allow_any_instance_of(Railbow::Formatters::Base).to receive(:bold).and_raise(NoMethodError, "boom")
    allow(Railbow).to receive(:record_failure)
    out, = render

    expect(out).to include("| Name").and include("Code LOC:")
    expect(out).not_to include("│")
  end
end
