# frozen_string_literal: true

namespace :railbow do
  desc "Generate a railbow config file with commented defaults"
  task :init do
    require "railbow/init"

    Railbow::Init.run
  end
end
