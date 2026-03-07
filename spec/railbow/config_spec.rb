# frozen_string_literal: true

require "spec_helper"
require "railbow/config"
require "tmpdir"

RSpec.describe Railbow::Config do
  before do
    described_class.root = "/tmp/railbow_test_nonexistent"
  end

  after do
    described_class.reset!
    ENV.delete("XDG_CONFIG_HOME")
  end

  describe ".load" do
    it "returns gem defaults when no config file exists" do
      config = described_class.load
      expect(config.dig("aliases", "columns", "Status")).to eq("Live")
      expect(config.dig("aliases", "values", "Status", "up")).to eq("↑↑")
      expect(config.dig("aliases", "values", "Status", "down")).to eq("↓↓")
    end

    it "memoizes the loaded config" do
      first = described_class.load
      second = described_class.load
      expect(first).to equal(second)
    end

    it "merges all layers: global + project + local" do
      Dir.mktmpdir do |dir|
        global_dir = File.join(dir, "global")
        project_dir = File.join(dir, "project")
        FileUtils.mkdir_p(global_dir)
        FileUtils.mkdir_p(project_dir)

        ENV["XDG_CONFIG_HOME"] = File.join(dir, "xdg")
        railbow_global = File.join(dir, "xdg", "railbow")
        FileUtils.mkdir_p(railbow_global)

        # Global: adds a Verb alias
        File.write(File.join(railbow_global, "config.yml"), <<~YAML)
          aliases:
            values:
              Verb:
                GET: G
        YAML

        # Project: overrides Status up
        File.write(File.join(project_dir, ".railbow.yml"), <<~YAML)
          aliases:
            values:
              Status:
                up: UP
        YAML

        # Local: overrides Status down
        File.write(File.join(project_dir, ".railbow.local.yml"), <<~YAML)
          aliases:
            values:
              Status:
                down: DN
        YAML

        described_class.root = project_dir
        config = described_class.load

        # Global layer added Verb
        expect(config.dig("aliases", "values", "Verb", "GET")).to eq("G")
        # Project layer overrode Status up
        expect(config.dig("aliases", "values", "Status", "up")).to eq("UP")
        # Local layer overrode Status down
        expect(config.dig("aliases", "values", "Status", "down")).to eq("DN")
        # Gem default columns preserved
        expect(config.dig("aliases", "columns", "Status")).to eq("Live")
      end
    end
  end

  describe ".column_aliases" do
    it "returns column alias map" do
      expect(described_class.column_aliases).to eq("Status" => "Live")
    end
  end

  describe ".value_aliases" do
    it "returns value alias map" do
      aliases = described_class.value_aliases
      expect(aliases["Status"]["up"]).to eq("↑↑")
      expect(aliases["Status"]["down"]).to eq("↓↓")
    end
  end

  describe ".table_aliases" do
    it "returns combined aliases hash with column and value keys" do
      result = described_class.table_aliases
      expect(result[:columns]).to eq("Status" => "Live")
      expect(result[:values]["Status"]["up"]).to eq("↑↑")
    end
  end

  describe ".deep_merge" do
    it "recursively merges hashes" do
      base = {"a" => {"b" => 1, "c" => 2}}
      override = {"a" => {"b" => 10, "d" => 3}}
      result = described_class.deep_merge(base, override)
      expect(result).to eq("a" => {"b" => 10, "c" => 2, "d" => 3})
    end

    it "replaces non-hash values" do
      base = {"a" => 1}
      override = {"a" => 2}
      expect(described_class.deep_merge(base, override)).to eq("a" => 2)
    end
  end

  describe ".global_dir" do
    it "defaults to ~/.config/railbow" do
      ENV.delete("XDG_CONFIG_HOME")
      expect(described_class.global_dir).to eq(File.join(Dir.home, ".config", "railbow"))
    end

    it "respects XDG_CONFIG_HOME" do
      ENV["XDG_CONFIG_HOME"] = "/custom/xdg"
      expect(described_class.global_dir).to eq("/custom/xdg/railbow")
    end

    it "ignores empty XDG_CONFIG_HOME" do
      ENV["XDG_CONFIG_HOME"] = ""
      expect(described_class.global_dir).to eq(File.join(Dir.home, ".config", "railbow"))
    end
  end

  describe ".config_files" do
    it "returns empty array when no config files exist" do
      expect(described_class.config_files).to eq([])
    end

    it "finds .railbow.yml in root" do
      Dir.mktmpdir do |dir|
        described_class.root = dir
        path = File.join(dir, ".railbow.yml")
        File.write(path, "aliases: {}")
        expect(described_class.config_files).to eq([path])
      end
    end

    it "prefers .railbow.yml over .railbow.yaml" do
      Dir.mktmpdir do |dir|
        described_class.root = dir
        File.write(File.join(dir, ".railbow.yml"), "aliases: {}")
        File.write(File.join(dir, ".railbow.yaml"), "aliases: {}")
        expect(described_class.config_files.length).to eq(1)
        expect(described_class.config_files.first).to end_with(".railbow.yml")
      end
    end

    it "returns files in order: global, project, local" do
      Dir.mktmpdir do |dir|
        ENV["XDG_CONFIG_HOME"] = File.join(dir, "xdg")
        railbow_global = File.join(dir, "xdg", "railbow")
        FileUtils.mkdir_p(railbow_global)

        project_dir = File.join(dir, "project")
        FileUtils.mkdir_p(project_dir)

        File.write(File.join(railbow_global, "config.yml"), "aliases: {}")
        File.write(File.join(project_dir, ".railbow.yml"), "aliases: {}")
        File.write(File.join(project_dir, ".railbow.local.yml"), "aliases: {}")

        described_class.root = project_dir
        files = described_class.config_files

        expect(files.length).to eq(3)
        expect(files[0]).to include("xdg/railbow/config.yml")
        expect(files[1]).to end_with(".railbow.yml")
        expect(files[2]).to end_with(".railbow.local.yml")
      end
    end
  end

  describe ".root" do
    it "can be overridden for testing" do
      described_class.root = "/custom/path"
      expect(described_class.root).to eq("/custom/path")
    end

    it "clears memoized config when root changes" do
      first = described_class.load
      described_class.root = "/other/path"
      second = described_class.load
      expect(first).not_to equal(second)
    end
  end

  describe ".reset!" do
    it "clears root and memoized config" do
      described_class.root = "/custom"
      described_class.load
      described_class.reset!
      expect(described_class.root).not_to eq("/custom")
    end
  end

  describe ".read_yaml" do
    it "returns hash from valid YAML file" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "test.yml")
        File.write(path, "key: value")
        expect(described_class.read_yaml(path)).to eq("key" => "value")
      end
    end

    it "returns empty hash for invalid YAML" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "bad.yml")
        File.write(path, "{{invalid")
        expect { described_class.read_yaml(path) }.to output(/Warning/).to_stderr
      end
    end

    it "returns empty hash when YAML parses to non-hash" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "list.yml")
        File.write(path, "- item1\n- item2")
        expect(described_class.read_yaml(path)).to eq({})
      end
    end
  end
end
