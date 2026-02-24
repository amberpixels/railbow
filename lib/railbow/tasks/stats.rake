# frozen_string_literal: true

# Defer prepend until CodeStatistics is available.
# CodeStatistics is autoloaded by Rails when the `stats` task runs,
# but is not available at rake-file load time.
Rails.application.config.after_initialize do
  require "code_statistics"
  require_relative "../stats_formatter"
  CodeStatistics.prepend(Railbow::StatsFormatter)
rescue LoadError
  # code_statistics not available (e.g., production without railties dev deps)
end
