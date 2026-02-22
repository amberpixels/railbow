# frozen_string_literal: true

require "railbow"
require "railbow/formatters/base"
require "railbow/migration_formatter"
require "railbow/migration_parser"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
end
