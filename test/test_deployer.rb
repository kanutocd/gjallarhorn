# frozen_string_literal: true

require "test_helper"
require "tempfile"

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
        deployer.deploy("production", "myapp:v1.0.0")
      end

      adapter_mock.verify
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
