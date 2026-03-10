# frozen_string_literal: true

require "yaml"

module Railbow
  module Config
    GEM_DEFAULTS = {
      "aliases" => {
        "columns" => {
          "Status" => "Live"
        },
        "values" => {
          "Status" => {"up" => "↑↑", "down" => "↓↓"}
        }
      },
      "since" => "70d",
      "git" => "author:me,diff,mask:auto",
      "view" => "calendar,tables",
      "calendar" => "wticks"
    }.freeze

    @root = nil
    @loaded = nil

    module_function

    # Overridable root for config file lookup. Defaults to Rails.root or Dir.pwd.
    def root
      @root || ((defined?(Rails) && Rails.respond_to?(:root) && Rails.root) ? Rails.root.to_s : Dir.pwd)
    end

    def root=(path)
      @root = path
      @loaded = nil
    end

    def reset!
      @root = nil
      @loaded = nil
    end

    def global_dir
      xdg = ENV["XDG_CONFIG_HOME"]
      base = (xdg && !xdg.empty?) ? xdg : File.join(Dir.home, ".config")
      File.join(base, "railbow")
    end

    def config_files
      files = []

      # 1. Global
      global = File.join(global_dir, "config.yml")
      files << global if File.exist?(global)

      # 2. Project .railbow.yml / .railbow.yaml
      %w[.railbow.yml .railbow.yaml].each do |name|
        full = File.join(root, name)
        if File.exist?(full)
          files << full
          break
        end
      end

      # 3. Local .railbow.local.yml / .railbow.local.yaml
      %w[.railbow.local.yml .railbow.local.yaml].each do |name|
        full = File.join(root, name)
        if File.exist?(full)
          files << full
          break
        end
      end

      files
    end

    def load
      @loaded ||= config_files.reduce(GEM_DEFAULTS.dup) { |acc, path| deep_merge(acc, read_yaml(path)) }
    end

    def column_aliases
      load.dig("aliases", "columns") || {}
    end

    def value_aliases
      load.dig("aliases", "values") || {}
    end

    def table_aliases
      {columns: column_aliases, values: value_aliases}
    end

    def read_yaml(path)
      content = begin
        YAML.safe_load_file(path)
      rescue Psych::SyntaxError, Psych::DisallowedClass
        warn "  Warning: failed to parse #{path}, using defaults"
        {}
      end
      content.is_a?(Hash) ? content : {}
    end

    def deep_merge(base, override)
      base.merge(override) do |_key, old_val, new_val|
        if old_val.is_a?(Hash) && new_val.is_a?(Hash)
          deep_merge(old_val, new_val)
        else
          new_val
        end
      end
    end
  end
end
