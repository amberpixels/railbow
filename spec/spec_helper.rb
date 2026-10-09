# frozen_string_literal: true

# Dates render on the local clock by default; pinning it keeps every spec
# that checks a rendered date independent of the machine running it.
ENV["TZ"] = "UTC"

require "railbow"
require "railbow/formatters/base"
require "railbow/migration_formatter"
require "railbow/migration_parser"

RSpec.configure do |config|
  # A failure switches railbow off for the rest of the process; each example
  # starts with it on.
  config.before { Railbow.failure = nil }

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
end
