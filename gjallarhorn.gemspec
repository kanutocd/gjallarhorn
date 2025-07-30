# frozen_string_literal: true

require_relative "lib/gjallarhorn/version"

Gem::Specification.new do |spec|
  spec.name = "gjallarhorn"
  spec.version = Gjallarhorn::VERSION
  spec.authors = ["Ken C. Demanawa"]
  spec.email = ["kenneth.c.demanawa@gmail.com"]

  spec.summary = "Multi-cloud deployment guardian as legendary as Heimdall's horn."
  spec.description = "A Ruby gem that sounds across all cloud realms with secure, API-first deployments beyond SSH."
  spec.homepage = "https://github.com/kanutocd/gjallarhorn"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/kanutocd/gjallarhorn"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/ .github/ .rubocop.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "thor", "~> 1.0"
  spec.add_dependency "aws-sdk-ssm", "~> 1.0"
  spec.add_dependency "aws-sdk-ec2", "~> 1.0"

  spec.add_development_dependency "irb"
  spec.add_development_dependency "minitest", "~> 5.16"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rubocop", "~> 1.21"
  spec.add_development_dependency "rubocop-minitest", "~> 0.38.1"
  spec.add_development_dependency "rubocop-rake", "~> 0.7.1"
  spec.add_development_dependency "simplecov", "~> 0.22"
end
