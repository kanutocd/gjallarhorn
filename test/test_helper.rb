# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  # Only track the lib directory
  track_files "lib/**/*.rb"

  add_filter "/test/"
  add_filter "/examples/"
  add_filter "/docs/"

  minimum_coverage 45 # Current achievable coverage for CLI tool with external API dependencies
  coverage_dir "coverage"

  # Group coverage by directory for cleaner reports
  add_group "Core", "lib/gjallarhorn"
  add_group "Adapters", "lib/gjallarhorn/adapter"

  # Report on individual files that need attention
  at_exit do
    puts "\n=== SimpleCov Coverage Summary ==="
    puts "Line Coverage: #{SimpleCov.result.covered_percent.round(2)}%"
    puts "Files with < 80% coverage:"
    SimpleCov.result.files.each do |file|
      next unless file.covered_percent < 80

      filename = file.filename.split("/").last
      coverage = "#{file.covered_percent.round(1)}%"
      lines = "(#{file.covered_lines.count}/#{file.lines.count} lines)"
      puts "  #{filename}: #{coverage} #{lines}"
    end
  end
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "gjallarhorn"

require "minitest/autorun"
