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

    # Load custom Rake tasks
    rake_tasks do
      load "railbow/tasks/migrate_status.rake"
    end
  end
end
