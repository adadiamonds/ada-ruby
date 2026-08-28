# frozen_string_literal: true

require_relative "lib/adadiamonds/version"

Gem::Specification.new do |spec|
  spec.name = "adadiamonds"
  spec.version = AdaDiamonds::VERSION
  spec.authors = ["Ada Diamonds"]
  spec.email = ["it@adadiamonds.com"]

  spec.summary = "Official Ruby client for the Ada Diamonds API"
  spec.description = "Search live lab grown diamond inventory, engagement ring settings, fine jewelry, " \
                     "showrooms, and the diamond buying guides at adadiamonds.com. Standard library only; " \
                     "no account or API key needed to read the catalog."
  spec.homepage = "https://www.adadiamonds.com/developers"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "documentation_uri" => "https://www.adadiamonds.com/developers/cli",
    "source_code_uri" => "https://github.com/adadiamonds/ada-ruby",
    "changelog_uri" => "https://github.com/adadiamonds/ada-ruby/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "https://github.com/adadiamonds/ada-ruby/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb"] + %w[README.md CHANGELOG.md LICENSE]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "webrick", "~> 1.7"
end
