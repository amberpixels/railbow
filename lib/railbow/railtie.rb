# frozen_string_literal: true

require "rails/railtie"

module Railbow
  class Railtie < Rails::Railtie
    # on_load, so booting the app does not force ActiveRecord to load early.
    initializer "railbow.enhance_migrations" do
      ActiveSupport.on_load(:active_record) do
        require_relative "migration_formatter"

        ActiveRecord::Migration.prepend(Railbow::MigrationFormatter)
      end
    end

    initializer "railbow.enhance_routes", after: :load_config_initializers do
      require "action_dispatch/routing/inspector"
      require_relative "routes_formatter"
      ActionDispatch::Routing::ConsoleFormatter::Sheet.prepend(Railbow::RoutesFormatter)
    end

    initializer "railbow.enhance_about", after: :load_config_initializers do
      require_relative "about_formatter"
      Rails::Info.singleton_class.prepend(Railbow::AboutFormatter)
    end

    initializer "railbow.enhance_notes", after: :load_config_initializers do
      require "rails/source_annotation_extractor"
      require_relative "notes_formatter"
      Rails::SourceAnnotationExtractor.prepend(Railbow::NotesFormatter)
    end

    # Since Rails 8.0 `rails stats` is a Rails command that boots the app but
    # never loads rake tasks, so the .rake file alone cannot install this.
    initializer "railbow.enhance_stats", after: :load_config_initializers do
      require_relative "stats_formatter"
      Railbow::StatsFormatter.install!
    end

    rake_tasks do
      load "railbow/tasks/migrate_status.rake"
      load "railbow/tasks/stats.rake"
      load "railbow/tasks/init.rake"
    end
  end
end
