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

    # Load custom Rake tasks
    rake_tasks do
      load "railbow/tasks/migrate_status.rake"
    end
  end
end
