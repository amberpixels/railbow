# frozen_string_literal: true

require_relative "railbow/version"
require_relative "railbow/params"
require_relative "railbow/config"

module Railbow
  class Error < StandardError; end

  # True when railbow should leave the stock Rails output alone. RBW_PLAIN
  # always wins; RBW_FORCE beats every auto-detection below it.
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

  # A railbow bug must never break the Rails command it decorates: an error
  # falls back to the stock output and switches railbow off for the process.
  # Errors Rails raises inside the fallback still propagate.
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

require_relative "railbow/railtie" if defined?(Rails::Railtie)
