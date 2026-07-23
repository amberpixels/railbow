# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in railbow.gemspec
gemspec

gem "irb", "~> 1.18"
gem "rake", "~> 13.4"
gem "rspec", "~> 3.13"
gem "benchmark", "~> 0.5"
gem "standard", "~> 1.54"

# Optional integration: recovers ghost migrations in migrate:status
gem "mighost", "~> 0.5"

# RAILS_VERSION lets CI test against multiple Rails releases
gem "rails", ENV.fetch("RAILS_VERSION", "~> 8.1")
