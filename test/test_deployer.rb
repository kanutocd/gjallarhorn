# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

class TestDeployer < Minitest::Test
  def setup
    @config = {
      "production" => {
        "provider" => "aws",
        "region" => "us-east-1",
        "environment" => "production",
        "services" => [
          {
            "name" => "web",
            "ports" => ["3000"],
            "replicas" => 3
          }
        ]
      },
      "unsupported" => {
        "provider" => "gcp"
      }
    }
  end

  def test_initializes_with_configuration
    with_config_file(@config) do |file|
      deployer = Gjallarhorn::Deployer.new(file.path)
      assert_kind_of Gjallarhorn::Configuration, deployer.configuration
      assert_kind_of Logger, deployer.logger
    end
  end

  def test_raises_error_for_unsupported_provider
    with_config_file(@config) do |file|
      deployer = Gjallarhorn::Deployer.new(file.path)

      error = assert_raises(Gjallarhorn::DeploymentError) do
        deployer.deploy("unsupported", "myapp:v1.0.0")
      end

      assert_match(/Provider 'gcp' not yet implemented/, error.message)
    end
  end

  def test_status_raises_error_for_unsupported_provider
    with_config_file(@config) do |file|
      deployer = Gjallarhorn::Deployer.new(file.path)

      error = assert_raises(Gjallarhorn::DeploymentError) do
        deployer.status("unsupported")
      end

      assert_match(/Provider 'gcp' not yet implemented/, error.message)
    end
  end

  def test_rollback_raises_error_for_unsupported_provider
    with_config_file(@config) do |file|
      deployer = Gjallarhorn::Deployer.new(file.path)

      error = assert_raises(Gjallarhorn::DeploymentError) do
        deployer.rollback("unsupported", "v1.0.0")
      end

      assert_match(/Provider 'gcp' not yet implemented/, error.message)
    end
  end

  def test_passes_environment_configuration_to_adapter
    with_config_file(@config) do |file|
      deployer = Gjallarhorn::Deployer.new(file.path)

      # Mock the AWS adapter to verify it receives the correct config
      adapter_mock = Minitest::Mock.new
      adapter_mock.expect(:deploy, nil) do |params|
        params[:image] == "myapp:v1.0.0" &&
          params[:environment] == "production" &&
          params[:services] == @config["production"]["services"]
      end

      Gjallarhorn::Adapter::AWSAdapter.stub(:new, adapter_mock) do
        deployer.deploy("production", "myapp:v1.0.0", strategy: "legacy")
      end

      adapter_mock.verify
    end
  end

  def test_deploy_records_history_on_success
    with_config_file(@config) do |file|
      # Create temporary history directory
      history_dir = Dir.mktmpdir
      
      # Mock history with temp directory
      history_mock = Gjallarhorn::History.new(history_dir: history_dir)
      
      # Create deployer with mocked history
      Gjallarhorn::History.stub(:new, history_mock) do
        deployer = Gjallarhorn::Deployer.new(file.path)
        
        # Mock the AWS adapter to succeed
        adapter_mock = Minitest::Mock.new
        adapter_mock.expect(:deploy, nil) do |params|
          params[:image] == "myapp:v1.0.0"
        end
        
        Gjallarhorn::Adapter::AWSAdapter.stub(:new, adapter_mock) do
          deployer.deploy("production", "myapp:v1.0.0", strategy: "legacy")
        end
        
        adapter_mock.verify
      end
      
      # Verify history was recorded
      history_records = history_mock.get_history(environment: "production")
      
      # Should have 2 records: started and success
      assert_equal 2, history_records.length
      
      success_record = history_records.find { |r| r["status"] == "success" }
      started_record = history_records.find { |r| r["status"] == "started" }
      
      assert success_record, "Should have a success record"
      assert started_record, "Should have a started record"
      
      assert_equal "production", success_record["environment"]
      assert_equal "myapp:v1.0.0", success_record["image"]
      assert_equal "legacy", success_record["strategy"]
    ensure
      FileUtils.rm_rf(history_dir) if history_dir
    end
  end

  def test_deploy_records_history_on_failure
    with_config_file(@config) do |file|
      # Create temporary history directory
      history_dir = Dir.mktmpdir
      
      # Mock history with temp directory
      history_mock = Gjallarhorn::History.new(history_dir: history_dir)
      
      # Create deployer with mocked history
      Gjallarhorn::History.stub(:new, history_mock) do
        deployer = Gjallarhorn::Deployer.new(file.path)
        
        # Mock the AWS adapter to fail
        adapter_mock = Minitest::Mock.new
        adapter_mock.expect(:deploy, nil) do |params|
          raise StandardError, "Deployment failed"
        end
        
        Gjallarhorn::Adapter::AWSAdapter.stub(:new, adapter_mock) do
          assert_raises(StandardError) do
            deployer.deploy("production", "myapp:v1.0.0", strategy: "legacy")
          end
        end
        
        adapter_mock.verify
      end
      
      # Verify history was recorded
      history_records = history_mock.get_history(environment: "production")
      
      # Should have 2 records: started and failed
      assert_equal 2, history_records.length
      
      failed_record = history_records.find { |r| r["status"] == "failed" }
      started_record = history_records.find { |r| r["status"] == "started" }
      
      assert failed_record, "Should have a failed record"
      assert started_record, "Should have a started record"
      
      assert_equal "production", failed_record["environment"]
      assert_equal "myapp:v1.0.0", failed_record["image"]
      assert_equal "legacy", failed_record["strategy"]
      assert_equal "Deployment failed", failed_record["error"]
    ensure
      FileUtils.rm_rf(history_dir) if history_dir
    end
  end

  def test_rollback_records_history_on_success
    with_config_file(@config) do |file|
      # Create temporary history directory
      history_dir = Dir.mktmpdir
      
      # Mock history with temp directory
      history_mock = Gjallarhorn::History.new(history_dir: history_dir)
      
      # Create deployer with mocked history
      Gjallarhorn::History.stub(:new, history_mock) do
        deployer = Gjallarhorn::Deployer.new(file.path)
        
        # Mock the AWS adapter to succeed
        adapter_mock = Minitest::Mock.new
        adapter_mock.expect(:rollback, nil, version: "v1.0.0")
        
        Gjallarhorn::Adapter::AWSAdapter.stub(:new, adapter_mock) do
          deployer.rollback("production", "v1.0.0")
        end
        
        adapter_mock.verify
      end
      
      # Verify history was recorded
      history_records = history_mock.get_history(environment: "production")
      
      # Should have 2 records: started and success
      assert_equal 2, history_records.length
      
      success_record = history_records.find { |r| r["status"] == "success" }
      
      assert success_record, "Should have a success record"
      assert_equal "production", success_record["environment"]
      assert_equal "v1.0.0", success_record["image"]
      assert_equal "rollback", success_record["strategy"]
    ensure
      FileUtils.rm_rf(history_dir) if history_dir
    end
  end

  def test_rollback_records_history_on_failure
    with_config_file(@config) do |file|
      # Create temporary history directory
      history_dir = Dir.mktmpdir
      
      # Mock history with temp directory
      history_mock = Gjallarhorn::History.new(history_dir: history_dir)
      
      # Create deployer with mocked history
      Gjallarhorn::History.stub(:new, history_mock) do
        deployer = Gjallarhorn::Deployer.new(file.path)
        
        # Mock the AWS adapter to fail
        adapter_mock = Minitest::Mock.new
        adapter_mock.expect(:rollback, nil) do |version:|
          raise StandardError, "Rollback failed"
        end
        
        Gjallarhorn::Adapter::AWSAdapter.stub(:new, adapter_mock) do
          assert_raises(StandardError) do
            deployer.rollback("production", "v1.0.0")
          end
        end
        
        adapter_mock.verify
      end
      
      # Verify history was recorded
      history_records = history_mock.get_history(environment: "production")
      
      # Should have 2 records: started and failed
      assert_equal 2, history_records.length
      
      failed_record = history_records.find { |r| r["status"] == "failed" }
      
      assert failed_record, "Should have a failed record"
      assert_equal "production", failed_record["environment"]
      assert_equal "v1.0.0", failed_record["image"]
      assert_equal "rollback", failed_record["strategy"]
      assert_equal "Rollback failed", failed_record["error"]
    ensure
      FileUtils.rm_rf(history_dir) if history_dir
    end
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
end
