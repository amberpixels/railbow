# frozen_string_literal: true

require "spec_helper"
require "active_support/core_ext/module/attribute_accessors"
require "rails/info"
require "railbow/about_formatter"

RSpec.describe Railbow::AboutFormatter do
  let(:info) do
    Module.new do
      mattr_accessor :properties, default: []
    end.tap { |mod| mod.singleton_class.prepend(described_class) }
  end

  let(:schema_version) { (Time.now.utc - (2 * 3600) - 60).strftime("%Y%m%d%H%M%S") }

  before do
    allow(Railbow).to receive(:plain?).and_return(false)
    info.properties = [
      ["Rails version", "8.1.4"],
      ["Ruby version", "ruby 4.0.6 (2026-07-14 revision 03b6d3f889) +PRISM [arm64-darwin25]"],
      ["Middleware", ["Rack::Sendfile", "ActionDispatch::Static"]],
      ["Application root", "/srv/pawshop"],
      ["Environment", "development"],
      ["Database schema version", schema_version.to_i],
      ["Pawshop flavor", "crunchy"]
    ]
  end

  def strip_ansi(str)
    str.gsub(/\e\[[0-9;]*m/, "")
  end

  def line_for(output, name)
    output.lines.find { |l| strip_ansi(l).start_with?(name) }
  end

  it "keeps the Rails title line" do
    expect(strip_ansi(info.to_s).lines.first.chomp).to eq("About your application's environment")
  end

  it "aligns the values in one column" do
    lines = strip_ansi(info.to_s).lines.drop(1)
    starts = lines.map { |l| l.index(/(?<=   )\S/) }

    expect(starts.uniq.size).to eq(1)
  end

  it "accents the version number and dims what trails it" do
    line = line_for(info.to_s, "Ruby version")

    expect(line).to include("ruby \e[36m4.0.6\e[0m")
    expect(line).to include("\e[2m (2026-07-14")
  end

  it "accents a bare version number" do
    expect(line_for(info.to_s, "Rails version")).to include("\e[36m8.1.4\e[0m")
  end

  it "prints list values one per line" do
    lines = strip_ansi(info.to_s).lines

    expect(lines.find { |l| l.start_with?("Middleware") }).to include("Rack::Sendfile")
    expect(lines).to include(a_string_matching(/\A\s+ActionDispatch::Static$/))
  end

  it "dims the application root" do
    expect(line_for(info.to_s, "Application root")).to include("\e[2m/srv/pawshop\e[0m")
  end

  it "shows the schema version's time and age" do
    line = strip_ansi(line_for(info.to_s, "Database schema version"))
    time = Time.utc(*schema_version.unpack("a4a2a2a2a2").map(&:to_i))

    expect(line).to include("#{schema_version}  (#{time.strftime("%Y-%m-%d %H:%M")} UTC, ~2hr ago)")
  end

  it "leaves a schema version that is not a timestamp alone" do
    info.properties = [["Database schema version", 0]]

    expect(strip_ansi(line_for(info.to_s, "Database schema version")).strip).to end_with("0")
  end

  it "renders properties railbow does not know as plain text" do
    expect(line_for(info.to_s, "Pawshop flavor")).to end_with("   crunchy")
  end

  describe "the environment" do
    {
      "production" => "\e[1m\e[31mproduction",
      "development" => "\e[32mdevelopment",
      "test" => "\e[33mtest",
      "staging" => "\e[33mstaging"
    }.each do |env, styled|
      it "styles #{env}" do
        info.properties = [["Environment", env]]

        expect(line_for(info.to_s, "Environment")).to include(styled)
      end
    end
  end

  it "reads the properties Rails registered" do
    Rails::Info.singleton_class.prepend(described_class)

    expect(strip_ansi(Rails::Info.to_s)).to include("Ruby version")
  end
end
