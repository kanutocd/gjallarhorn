# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "stringio"
require "json"

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

  def test_deploy_successful_with_valid_config
    with_config_file(@config) do |file|
      # Mock the deployer to avoid AWS SDK issues
      deployer_mock = Minitest::Mock.new
      deployer_mock.expect(:deploy, nil, ["production", "myapp:v1.0.0"])

      Gjallarhorn::Deployer.stub(:new, deployer_mock) do
        capture_output do
          Gjallarhorn::CLI.start(["deploy", "production", "myapp:v1.0.0", "--config", file.path])
        end

        # Should complete without error
        assert true
      end

      deployer_mock.verify
    end
  end

  def test_status_successful_with_valid_config
    with_config_file(@config) do |file|
      # Mock the deployer to return status
      deployer_mock = Minitest::Mock.new
      deployer_mock.expect(:status, ["Service: web - Status: running"], ["production"])

      Gjallarhorn::Deployer.stub(:new, deployer_mock) do
        output = capture_output do
          Gjallarhorn::CLI.start(["status", "production", "--config", file.path])
        end

        assert_match "Status for production", output
      end

      deployer_mock.verify
    end
  end

  def test_rollback_successful_with_valid_config
    with_config_file(@config) do |file|
      # Mock the deployer
      deployer_mock = Minitest::Mock.new
      deployer_mock.expect(:rollback, nil, ["production", "v1.0.0"])

      Gjallarhorn::Deployer.stub(:new, deployer_mock) do
        capture_output do
          Gjallarhorn::CLI.start(["rollback", "production", "v1.0.0", "--config", file.path])
        end

        # Should complete without error
        assert true
      end

      deployer_mock.verify
    end
  end

  def test_history_command_with_empty_history
    # Create empty history directory
    history_dir = Dir.mktmpdir
    
    Gjallarhorn::History.stub(:new, Gjallarhorn::History.new(history_dir: history_dir)) do
      output, status = capture_output_and_status do
        Gjallarhorn::CLI.start(["history", "production"])
      end

      assert_equal 0, status
      assert_match(/No deployment history found for production/, output)
    end
  ensure
    FileUtils.rm_rf(history_dir) if history_dir
  end

  def test_history_command_with_records
    # Create a temporary history file with some records
    history_dir = Dir.mktmpdir
    history_file = File.join(history_dir, "history.json")
    
    history_data = [
      {
        "timestamp" => "2023-07-29T10:00:00Z",
        "environment" => "production",
        "image" => "myapp:v1.0.0",
        "status" => "success",
        "strategy" => "zero_downtime"
      },
      {
        "timestamp" => "2023-07-29T09:00:00Z",
        "environment" => "production", 
        "image" => "myapp:v0.9.0",
        "status" => "failed",
        "strategy" => "zero_downtime",
        "error" => "Health check failed"
      }
    ]
    
    File.write(history_file, JSON.pretty_generate(history_data))
    
    # Mock the History class to use our temp directory
    Gjallarhorn::History.stub(:new, Gjallarhorn::History.new(history_dir: history_dir)) do
      output = capture_output do
        Gjallarhorn::CLI.start(["history", "production"])
      end
      
      assert_match(/Deployment history for production/, output)
      assert_match(/myapp:v1\.0\.0/, output)
      assert_match(/myapp:v0\.9\.0/, output)
      assert_match(/success/, output)
      assert_match(/failed/, output)
      assert_match(/Health check failed/, output)
      assert_match(/Statistics:/, output)
      assert_match(/Success rate: 50\.0%/, output)
    end
  ensure
    FileUtils.rm_rf(history_dir) if history_dir
  end

  def test_history_command_with_limit_option
    # Create some history records
    history_dir = Dir.mktmpdir
    history_file = File.join(history_dir, "history.json")
    
    history_data = (1..5).map do |i|
      {
        "timestamp" => "2023-07-29T#{10 + i}:00:00Z",
        "environment" => "production",
        "image" => "myapp:v1.#{i}.0",
        "status" => "success",
        "strategy" => "zero_downtime"
      }
    end
    
    File.write(history_file, JSON.pretty_generate(history_data))
    
    # Mock the History class and test with limit
    Gjallarhorn::History.stub(:new, Gjallarhorn::History.new(history_dir: history_dir)) do
      output = capture_output do
        Gjallarhorn::CLI.start(["history", "production", "--limit", "2"])
      end
      
      # Should only show 2 records (most recent first)
      assert_match(/myapp:v1\.5\.0/, output)  # Most recent
      assert_match(/myapp:v1\.4\.0/, output)  # Second most recent
      refute_match(/myapp:v1\.1\.0/, output)  # Should not appear due to limit
    end
  ensure
    FileUtils.rm_rf(history_dir) if history_dir
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
