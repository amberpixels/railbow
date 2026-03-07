# frozen_string_literal: true

require "spec_helper"
require "railbow/config"
require "rake"
require "tmpdir"

RSpec.describe "railbow:init rake task" do
  before(:all) do
    Rake.application = Rake::Application.new
    Rake.application.rake_require("railbow/tasks/init", $LOAD_PATH)
  end

  after do
    Railbow::Config.reset!
  end

  let(:task) { Rake::Task["railbow:init"] }

  before { task.reenable }

  it "creates .railbow.yml in project root" do
    Dir.mktmpdir do |dir|
      Railbow::Config.root = dir
      expect { task.invoke }.to output(/Created/).to_stdout

      path = File.join(dir, ".railbow.yml")
      expect(File.exist?(path)).to be true

      content = File.read(path)
      expect(content).to include("# Railbow configuration")
      expect(content).to include("aliases:")
      expect(content).to include(".railbow.local.yml")
    end
  end

  it "refuses to overwrite existing file" do
    Dir.mktmpdir do |dir|
      Railbow::Config.root = dir
      File.write(File.join(dir, ".railbow.yml"), "existing: true")

      expect { task.invoke }.to output(/Already exists/).to_stdout

      # Content unchanged
      expect(File.read(File.join(dir, ".railbow.yml"))).to eq("existing: true")
    end
  end

  it "prints config layer summary on creation" do
    Dir.mktmpdir do |dir|
      Railbow::Config.root = dir
      output = capture_stdout { task.invoke }

      expect(output).to include("Global:")
      expect(output).to include("Project:")
      expect(output).to include("Local:")
    end
  end

  private

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
