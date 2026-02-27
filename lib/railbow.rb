# frozen_string_literal: true

require_relative "railbow/version"
require_relative "railbow/params"

module Railbow
  class Error < StandardError; end

  # Returns true when Railbow formatting should be disabled.
  # Checks for explicit opt-out, standard conventions, CI, and LLM agents.
  def self.plain?
    return true if Params.plain?
    return true if ENV.key?("NO_COLOR")
    return true if ENV.key?("CLAUDECODE")
    return true if ENV.key?("CI")
    !$stdout.tty?
  end
end

# Load Railtie if Rails is available
require_relative "railbow/railtie" if defined?(Rails::Railtie)
