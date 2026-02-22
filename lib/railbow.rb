# frozen_string_literal: true

require_relative "railbow/version"

module Railbow
  class Error < StandardError; end
end

# Load Railtie if Rails is available
require_relative "railbow/railtie" if defined?(Rails::Railtie)
