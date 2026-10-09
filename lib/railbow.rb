# frozen_string_literal: true

require_relative "railbow/version"
require_relative "railbow/params"
require_relative "railbow/config"

module Railbow
  class Error < StandardError; end

  # Returns true when Railbow formatting should be disabled.
  # Checks for explicit opt-out, standard conventions, CI, and LLM agents.
  # RBW_PLAIN always wins; RBW_FORCE beats every auto-detection below it.
  def self.plain?
    return true if failure
    return true if Params.plain?
    return false if Params.force?
    return true if ENV.key?("NO_COLOR")
    return true if ENV.key?("CLAUDECODE")
    return true if ENV.key?("CI")
    !$stdout.tty?
  end

  class << self
    # The first error railbow's own rendering raised in this process. Once set,
    # railbow stays plain so a broken formatter cannot fail twice.
    attr_accessor :failure
  end

  # Runs railbow's rendering for a hooked Rails command. A railbow bug must
  # never break the command itself, so an error falls back to the stock Rails
  # output and switches railbow off for the rest of the process. Errors raised
  # by Rails inside the fallback still propagate, as they would without
  # railbow.
  def self.guard(fallback)
    yield
  rescue => e
    record_failure(e)
    fallback.call
  end

  def self.record_failure(error)
    return if failure

    self.failure = error
    frame = error.backtrace_locations&.find { |l| l.path.to_s.include?("/railbow/") }
    where = frame ? " at #{frame.path[%r{lib/railbow/.*}] || frame.path}:#{frame.lineno}" : ""
    warn "railbow: #{error.class}: #{error.message}#{where}; showing the default Rails output instead"
  end
end

# Load Railtie if Rails is available
require_relative "railbow/railtie" if defined?(Rails::Railtie)
