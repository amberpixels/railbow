# frozen_string_literal: true

require_relative "config"
require "fileutils"

module Railbow
  module Init
    module_function

    TEMPLATE = <<~YAML
      # Railbow configuration
      # https://github.com/amberpixels/railbow
      #
      # Config layers (each overrides the previous):
      #   1. Gem defaults (built-in)
      #   2. Global:  ~/.config/railbow/config.yml
      #   3. Project: .railbow.yml        (commit to git)
      #   4. Local:   .railbow.local.yml  (gitignored, personal overrides)
      #
      # Every key can also be overridden via RBW_* environment variables.

      # Time window for migrations to display (e.g. 30d, 2mo, 1y, all)
      since: "70d"

      # Sort order: file (by filename/version) or date (by timestamp)
      # sort: "file"

      # Git integration (comma-separated compound value):
      #   author       — add Author column (same as author:all)
      #   author:me    — highlight your own migrations
      #   author:all   — show all authors
      #   diff         — tag migrations by git origin branch
      #   base:<branch> — base branch for diff (default: auto-detected)
      #   mask:auto    — auto-extract ticket id from branch name
      #   mask:<re>    — custom regex to extract branch label, e.g. mask:(WS-[^/]+)/
      git: "author:me,diff,mask:auto"

      # View mode (comma-separated): calendar, tables
      view: "calendar,tables"

      # Calendar options: wticks (show week tick separators)
      calendar: "wticks"

      # Date format: full, rel, short, or custom(%b %d, %Y)
      # date: "full"

      # Compact mode (comma-separated):
      #   oneline       — one line per migration
      #   dense         — reduce padding
      #   noheader      — hide table headers
      #   maxw:<N>      — max column width
      #   hide:<col>    — hide a column (repeatable)
      # compact: ""

      # Rename column headers and cell values in table output
      aliases:
        columns:
          Status: Live
        values:
          Status:
            up: "↑↑"
            down: "↓↓"
          # Verb:
          #   GET: G
          #   POST: P
    YAML

    def global_path
      File.join(Config.global_dir, "config.yml")
    end

    def project_path
      File.join(Config.root, ".railbow.yml")
    end

    def run(input: $stdin, output: $stdout)
      output.puts "  Where should the config be created?"
      output.puts ""
      output.puts "    1) Global:  #{global_path}"
      output.puts "    2) Project: #{project_path}"
      output.puts "    3) Cancel"
      output.puts ""
      output.print "  Choose [1/2/3]: "
      output.flush

      choice = input.gets&.strip
      target = case choice
      when "1" then global_path
      when "2" then project_path
      else
        output.puts "  Cancelled."
        return
      end

      if File.exist?(target)
        output.puts "  Already exists: #{target}"
        output.puts "  Remove it first if you want to regenerate."
        return
      end

      FileUtils.mkdir_p(File.dirname(target))
      File.write(target, TEMPLATE)
      output.puts ""
      output.puts "  Created: #{target}"
    end
  end
end
