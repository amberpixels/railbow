# frozen_string_literal: true

require_relative "shine/version"

module Shine
  class Error < StandardError; end
end

# Load Railtie if Rails is available
require_relative "shine/railtie" if defined?(Rails::Railtie)
