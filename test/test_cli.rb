# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "stringio"

class TestCLI < Minitest::Test
  def setup
    @config = {
      "production" => {
        "provider" => "aws",
        "region" => "us-east-1",
        "environment" => "production"
      }
    }
  end

  def test_version_command_outputs_version
    output = capture_output do
      Gjallarhorn::CLI.start(["version"])
    end

    assert_match Gjallarhorn::VERSION, output
  end

  def test_config_command_shows_configuration
    with_config_file(@config) do |file|
      output = capture_output do
        Gjallarhorn::CLI.start(["config", "--config", file.path])
      end

      assert_match "production", output
      assert_match "provider: aws", output
    end
  end

  def test_deploy_command_with_missing_config_exits_with_error
    output, status = capture_output_and_status do
      Gjallarhorn::CLI.start(["deploy", "production", "myapp:v1.0.0", "--config", "nonexistent.yml"])
    end

    assert_equal 1, status
    assert_match "Deployment failed", output
    assert_match "not found", output
  end

  def test_status_command_with_missing_config_exits_with_error
    output, status = capture_output_and_status do
      Gjallarhorn::CLI.start(["status", "production", "--config", "nonexistent.yml"])
    end

    assert_equal 1, status
    assert_match "Status check failed", output
  end

  def test_rollback_command_with_missing_config_exits_with_error
    output, status = capture_output_and_status do
      Gjallarhorn::CLI.start(["rollback", "production", "v1.0.0", "--config", "nonexistent.yml"])
    end

    assert_equal 1, status
    assert_match "Rollback failed", output
  end

  def test_config_command_with_missing_file_exits_with_error
    output, status = capture_output_and_status do
      Gjallarhorn::CLI.start(["config", "--config", "nonexistent.yml"])
    end

    assert_equal 1, status
    assert_match "Configuration error", output
  end

  private

  def with_config_file(config_hash)
    file = Tempfile.new(["config", ".yml"])
    file.write(config_hash.to_yaml)
    file.close
    yield file
  ensure
    file&.unlink
  end

  def capture_output
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end

  def capture_output_and_status
    original_stdout = $stdout
    $stdout = StringIO.new

    status = 0
    begin
      yield
    rescue SystemExit => e
      status = e.status
    end

    [$stdout.string, status]
  ensure
    $stdout = original_stdout
  end
end
