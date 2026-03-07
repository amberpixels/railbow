# frozen_string_literal: true

require "rails/railtie"

module Railbow
  class Railtie < Rails::Railtie
    # Initialize after ActiveRecord is loaded
    initializer "railbow.enhance_migrations" do
      ActiveSupport.on_load(:active_record) do
        require_relative "migration_formatter"

        # Prepend our formatter module to ActiveRecord::Migration
        ActiveRecord::Migration.prepend(Railbow::MigrationFormatter)
      end
    end

    # Enhance routes output with colors
    initializer "railbow.enhance_routes", after: :load_config_initializers do
      require "action_dispatch/routing/inspector"
      require_relative "routes_formatter"
      ActionDispatch::Routing::ConsoleFormatter::Sheet.prepend(Railbow::RoutesFormatter)
    end

    # Enhance `rails about` output
    initializer "railbow.enhance_about", after: :load_config_initializers do
      require_relative "about_formatter"
      Rails::Info.singleton_class.prepend(Railbow::AboutFormatter)
    end

    # Enhance `rails notes` output
    initializer "railbow.enhance_notes", after: :load_config_initializers do
      require "rails/source_annotation_extractor"
      require_relative "notes_formatter"
      Rails::SourceAnnotationExtractor.prepend(Railbow::NotesFormatter)
    end

    # Load custom Rake tasks
    rake_tasks do
      load "railbow/tasks/migrate_status.rake"
      load "railbow/tasks/stats.rake"
      load "railbow/tasks/init.rake"
    end
  end
end
