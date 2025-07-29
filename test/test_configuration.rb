# frozen_string_literal: true

require "test_helper"
require "tempfile"

class TestConfiguration < Minitest::Test
  def setup
    @valid_config = {
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
      "staging" => {
        "provider" => "gcp",
        "project_id" => "test-project",
        "zone" => "us-central1-a"
      }
    }
  end

  def test_loads_configuration_from_file
    with_config_file(@valid_config) do |file|
      config = Gjallarhorn::Configuration.new(file.path)
      assert_equal @valid_config, config.data
    end
  end

  def test_environment_returns_environment_config
    with_config_file(@valid_config) do |file|
      config = Gjallarhorn::Configuration.new(file.path)
      env_config = config.environment("production")
      assert_equal @valid_config["production"], env_config
    end
  end

  def test_environment_raises_error_for_missing_environment
    with_config_file(@valid_config) do |file|
      config = Gjallarhorn::Configuration.new(file.path)

      error = assert_raises(Gjallarhorn::ConfigurationError) do
        config.environment("nonexistent")
      end

      assert_match(/Environment 'nonexistent' not found/, error.message)
    end
  end

  def test_environments_returns_all_environment_names
    with_config_file(@valid_config) do |file|
      config = Gjallarhorn::Configuration.new(file.path)
      assert_equal %w[production staging], config.environments
    end
  end

  def test_provider_for_returns_provider_name
    with_config_file(@valid_config) do |file|
      config = Gjallarhorn::Configuration.new(file.path)
      assert_equal "aws", config.provider_for("production")
      assert_equal "gcp", config.provider_for("staging")
    end
  end

  def test_services_for_returns_services_array
    with_config_file(@valid_config) do |file|
      config = Gjallarhorn::Configuration.new(file.path)
      services = config.services_for("production")
      assert_equal 1, services.length
      assert_equal "web", services.first["name"]
    end
  end

  def test_services_for_returns_empty_array_when_no_services
    with_config_file(@valid_config) do |file|
      config = Gjallarhorn::Configuration.new(file.path)
      services = config.services_for("staging")
      assert_empty services
    end
  end

  def test_raises_error_for_missing_file
    error = assert_raises(Gjallarhorn::ConfigurationError) do
      Gjallarhorn::Configuration.new("nonexistent.yml")
    end

    assert_match(/Configuration file 'nonexistent.yml' not found/, error.message)
  end

  def test_raises_error_for_invalid_yaml
    with_invalid_yaml_file do |file|
      error = assert_raises(Gjallarhorn::ConfigurationError) do
        Gjallarhorn::Configuration.new(file.path)
      end

      assert_match(/Invalid YAML/, error.message)
    end
  end

  def test_raises_error_for_empty_configuration
    with_config_file({}) do |file|
      error = assert_raises(Gjallarhorn::ConfigurationError) do
        Gjallarhorn::Configuration.new(file.path)
      end

      assert_match(/Configuration file is empty/, error.message)
    end
  end

  def test_raises_error_for_invalid_provider
    invalid_config = {
      "test" => {
        "provider" => "invalid_provider"
      }
    }

    with_config_file(invalid_config) do |file|
      error = assert_raises(Gjallarhorn::ConfigurationError) do
        Gjallarhorn::Configuration.new(file.path)
      end

      assert_match(/Invalid provider 'invalid_provider'/, error.message)
    end
  end

  def test_raises_error_for_missing_provider
    invalid_config = {
      "test" => {
        "region" => "us-east-1"
      }
    }

    with_config_file(invalid_config) do |file|
      error = assert_raises(Gjallarhorn::ConfigurationError) do
        Gjallarhorn::Configuration.new(file.path)
      end

      assert_match(/missing required 'provider' field/, error.message)
    end
  end

  def test_to_yaml_returns_yaml_string
    with_config_file(@valid_config) do |file|
      configuration = Gjallarhorn::Configuration.new(file.path)
      yaml_output = configuration.to_yaml

      assert_kind_of String, yaml_output
      assert_match "production", yaml_output
      assert_match "provider: aws", yaml_output
    end
  end

  def test_handles_symbol_environment_names
    with_config_file(@valid_config) do |file|
      configuration = Gjallarhorn::Configuration.new(file.path)

      # Should work with symbols
      env_config = configuration.environment(:production)
      assert_equal "aws", env_config["provider"]

      provider = configuration.provider_for(:staging)
      assert_equal "gcp", provider

      services = configuration.services_for(:production)
      assert_equal @valid_config["production"]["services"], services
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

  def with_invalid_yaml_file
    file = Tempfile.new(["config", ".yml"])
    file.write("invalid: yaml: content: [")
    file.close
    yield file
  ensure
    file&.unlink
  end
end
