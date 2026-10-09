# frozen_string_literal: true

require_relative "../stats_formatter"

# Rails 7.2 runs `rails stats` as a rake task that never boots the app, so the
# railtie initializer does not fire there: install from here as well.
Railbow::StatsFormatter.install!

# Rails 8.1 dropped the `stats` rake task for the `rails stats` command; this
# keeps `rake stats` working. Gated on the version, not task_defined?: railtie
# tasks load before Rails' own, so on older Rails both would run.
if Rails.gem_version >= Gem::Version.new("8.1")
  desc "Report code statistics (lines / LOC / classes / methods / M/C / LOC/M)"
  task stats: :environment do
    stat_directories = Rails::CodeStatistics.directories
      .map { |name, dir| [name, Rails.root.join(dir)] }
      .select { |_, dir| File.directory?(dir) }

    Rails::CodeStatistics.new(*stat_directories).to_s
  end
end
