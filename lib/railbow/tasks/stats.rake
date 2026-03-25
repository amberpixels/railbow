# frozen_string_literal: true

# Defer prepend until CodeStatistics is available.
# CodeStatistics is autoloaded by Rails when the `stats` task runs,
# but is not available at rake-file load time.
#
# Rails 8.1 namespaced the class to Rails::CodeStatistics, removed
# the bare `require "code_statistics"` shim, and dropped the built-in
# `stats` rake task. We handle both old and new layouts.
Rails.application.config.after_initialize do
  klass = nil

  begin
    require "rails/code_statistics"
    klass = Rails::CodeStatistics
  rescue LoadError
    # fall through
  end

  unless klass
    begin
      require "code_statistics"
      klass = CodeStatistics
    rescue LoadError
      # code_statistics not available (e.g., production without railties dev deps)
    end
  end

  if klass
    require_relative "../stats_formatter"
    klass.prepend(Railbow::StatsFormatter)
  end
end

# Rails 8.1 removed the built-in `stats` task.  Re-define it so that
# `rails stats` / `rake stats` keeps working with Railbow formatting.
unless Rake::Task.task_defined?(:stats)
  desc "Report code statistics (lines / LOC / classes / methods / M/C / LOC/M)"
  task stats: :environment do
    klass = if defined?(Rails::CodeStatistics)
      Rails::CodeStatistics
    elsif defined?(CodeStatistics)
      CodeStatistics
    end

    unless klass
      abort "CodeStatistics is not available. Make sure railties is loaded."
    end

    stat_directories = [
      ["Controllers", "app/controllers"],
      ["Helpers", "app/helpers"],
      ["Jobs", "app/jobs"],
      ["Models", "app/models"],
      ["Mailers", "app/mailers"],
      ["Channels", "app/channels"],
      ["JavaScripts", "app/javascript"],
      ["Libraries", "lib"],
      ["APIs", "app/apis"],
      ["Controller tests", "test/controllers"],
      ["Helper tests", "test/helpers"],
      ["Job tests", "test/jobs"],
      ["Model tests", "test/models"],
      ["Mailer tests", "test/mailers"],
      ["Channel tests", "test/channels"],
      ["Integration tests", "test/integration"],
      ["System tests", "test/system"],
      ["Controller specs", "spec/controllers"],
      ["Helper specs", "spec/helpers"],
      ["Job specs", "spec/jobs"],
      ["Model specs", "spec/models"],
      ["Mailer specs", "spec/mailers"],
      ["Channel specs", "spec/channels"],
      ["Request specs", "spec/requests"],
      ["System specs", "spec/system"]
    ]

    root = Rails.root.to_s
    pairs = stat_directories
      .map { |name, dir| [name, File.join(root, dir)] }
      .select { |_, dir| File.directory?(dir) }

    puts klass.new(*pairs)
  end
end
