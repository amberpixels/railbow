# frozen_string_literal: true

namespace :railbow do
  desc "Generate a .railbow.yml config file with commented defaults"
  task :init do
    require "railbow/config"

    target = File.join(Railbow::Config.root, ".railbow.yml")

    if File.exist?(target)
      puts "  Already exists: #{target}"
      puts "  Remove it first if you want to regenerate."
    else
      template = <<~YAML
        # Railbow configuration
        # https://github.com/amberpixels/railbow
        #
        # Config layers (each overrides the previous):
        #   1. Gem defaults (built-in)
        #   2. Global:  ~/.config/railbow/config.yml
        #   3. Project: .railbow.yml        (this file — commit to git)
        #   4. Local:   .railbow.local.yml  (gitignored, personal overrides)

        aliases:
          # Rename column headers
          columns:
            Status: Live

          # Replace cell values (matched after ANSI stripping)
          values:
            Status:
              up: "↑↑"
              down: "↓↓"
            # Verb:
            #   GET: G
            #   POST: P
      YAML

      File.write(target, template)
      puts "  Created: #{target}"
      puts ""
      puts "  Config layers (each overrides the previous):"
      puts "    1. Gem defaults (built-in)"
      puts "    2. Global:  #{Railbow::Config.global_dir}/config.yml"
      puts "    3. Project: .railbow.yml        (commit to git)"
      puts "    4. Local:   .railbow.local.yml  (gitignored, personal overrides)"
    end
  end
end
