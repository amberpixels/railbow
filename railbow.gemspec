# frozen_string_literal: true

require_relative "lib/railbow/version"

Gem::Specification.new do |spec|
  spec.name = "railbow"
  spec.version = Railbow::VERSION
  spec.authors = ["Eugene M"]
  spec.email = ["eugene@amberpixels.io"]

  spec.summary = "Enhance Rails migration output with modern, colorful, emoji-enhanced formatting"
  spec.description = "Railbow makes Rails database migrations beautiful with colorful output, emojis, and readable millisecond timing"
  spec.homepage = "https://github.com/amberpixels/railbow"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/amberpixels/railbow"
  spec.metadata["changelog_uri"] = "https://github.com/amberpixels/railbow/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.{rb,rake}", "exe/*", "sig/**/*.rbs"] +
    %w[LICENSE.txt README.md CHANGELOG.md]
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "railties", ">= 7.2", "< 8.2"
  spec.add_dependency "activerecord", ">= 7.2", "< 8.2"
  spec.add_dependency "unicode-display_width", "~> 3.0"
end
