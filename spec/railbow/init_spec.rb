# frozen_string_literal: true

require "spec_helper"
require "railbow/init"
require "tmpdir"

RSpec.describe Railbow::Init do
  after { Railbow::Config.reset! }

  def run_with_choice(choice)
    input = StringIO.new("#{choice}\n")
    output = StringIO.new
    described_class.run(input: input, output: output)
    output.string
  end

  it "creates project .railbow.yml when user chooses 2" do
    Dir.mktmpdir do |dir|
      Railbow::Config.root = dir
      result = run_with_choice("2")

      path = File.join(dir, ".railbow.yml")
      expect(File.exist?(path)).to be true
      expect(result).to include("Created")
    end
  end

  it "creates global config when user chooses 1" do
    Dir.mktmpdir do |dir|
      allow(Railbow::Config).to receive(:global_dir).and_return(File.join(dir, "railbow"))

      result = run_with_choice("1")

      path = File.join(dir, "railbow", "config.yml")
      expect(File.exist?(path)).to be true
      expect(result).to include("Created")
    end
  end

  it "cancels when user chooses 3" do
    Dir.mktmpdir do |dir|
      Railbow::Config.root = dir
      result = run_with_choice("3")

      expect(result).to include("Cancelled")
      expect(File.exist?(File.join(dir, ".railbow.yml"))).to be false
    end
  end

  it "cancels on empty input" do
    Dir.mktmpdir do |dir|
      Railbow::Config.root = dir
      result = run_with_choice("")

      expect(result).to include("Cancelled")
    end
  end

  it "template includes all config keys" do
    Dir.mktmpdir do |dir|
      Railbow::Config.root = dir
      run_with_choice("2")

      content = File.read(File.join(dir, ".railbow.yml"))
      expect(content).to include('since: "70d"')
      expect(content).to include('git: "author:me,diff,mask:auto"')
      expect(content).to include('view: "calendar,tables"')
      expect(content).to include('calendar: "wticks"')
      expect(content).to include("aliases:")
    end
  end

  it "refuses to overwrite existing file" do
    Dir.mktmpdir do |dir|
      Railbow::Config.root = dir
      File.write(File.join(dir, ".railbow.yml"), "existing: true")

      result = run_with_choice("2")
      expect(result).to include("Already exists")

      expect(File.read(File.join(dir, ".railbow.yml"))).to eq("existing: true")
    end
  end

  it "shows both paths in the prompt" do
    Dir.mktmpdir do |dir|
      Railbow::Config.root = dir
      result = run_with_choice("3")

      expect(result).to include("Global:")
      expect(result).to include("Project:")
    end
  end
end
