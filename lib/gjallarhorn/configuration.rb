# frozen_string_literal: true

require "yaml"

module Gjallarhorn
  # Configuration management class for loading and validating deployment configurations
  #
  # The Configuration class handles loading YAML configuration files that define
  # deployment environments, their providers, and associated services. It provides
  # validation to ensure all required fields are present and valid.
  #
  # @example Loading configuration
  #   config = Gjallarhorn::Configuration.new('deploy.yml')
  #   environments = config.environments
  #   production_config = config.environment('production')
  #
  # @example Accessing environment details
  #   provider = config.provider_for('staging')
  #   services = config.services_for('production')
  #
  # @since 0.1.0
  class Configuration
    # @return [String] Path to the configuration file
    attr_reader :config_file

    # @return [Hash] Loaded configuration data
    attr_reader :data

    # Initialize a new Configuration instance
    #
    # @param config_file [String] Path to the YAML configuration file
    # @raise [ConfigurationError] If the file doesn't exist or contains invalid YAML
    def initialize(config_file = "deploy.yml")
      @config_file = config_file
      load_configuration
    end

    # Get configuration for a specific environment
    #
    # @param name [String, Symbol] Environment name
    # @raise [ConfigurationError] If the environment is not found
    # @return [Hash] Environment configuration hash
    def environment(name)
      env_config = @data[name.to_s]
      raise ConfigurationError, "Environment '#{name}' not found in #{config_file}" unless env_config

      env_config
    end

    # Get all available environment names
    #
    # @return [Array<String>] List of environment names
    def environments
      @data.keys
    end

    # Get the provider for a specific environment
    #
    # @param environment [String, Symbol] Environment name
    # @return [String] Provider name (e.g., 'aws', 'gcp')
    def provider_for(environment)
      env_config = environment(environment)
      env_config["provider"]
    end

    # Get the services configuration for a specific environment
    #
    # @param environment [String, Symbol] Environment name
    # @return [Array<Hash>] List of service configurations
    def services_for(environment)
      env_config = environment(environment)
      env_config["services"] || []
    end

    # Convert configuration to YAML string
    #
    # @return [String] YAML representation of the configuration
    def to_yaml
      @data.to_yaml
    end

    private

    def load_configuration
      raise ConfigurationError, "Configuration file '#{config_file}' not found" unless File.exist?(config_file)

      @data = YAML.load_file(config_file)
      validate_configuration
    rescue Psych::SyntaxError => e
      raise ConfigurationError, "Invalid YAML in #{config_file}: #{e.message}"
    end

    def validate_configuration
      raise ConfigurationError, "Configuration file is empty" if @data.nil? || @data.empty?

      @data.each do |env_name, env_config|
        validate_environment(env_name, env_config)
      end
    end

    def validate_environment(env_name, env_config)
      validate_environment_structure(env_name, env_config)
      validate_provider_field(env_name, env_config)
      validate_provider_value(env_name, env_config["provider"])
    end

    def validate_environment_structure(env_name, env_config)
      return if env_config.is_a?(Hash)

      raise ConfigurationError, "Environment '#{env_name}' is not a hash"
    end

    def validate_provider_field(env_name, env_config)
      return if env_config["provider"]

      raise ConfigurationError,
            "Environment '#{env_name}' missing required 'provider' field"
    end

    def validate_provider_value(env_name, provider)
      valid_providers = %w[aws gcp azure docker kubernetes]
      return if valid_providers.include?(provider)

      valid_list = valid_providers.join(", ")
      raise ConfigurationError,
            "Invalid provider '#{provider}' for environment '#{env_name}'. Must be one of: #{valid_list}"
    end
  end

  # Raised when configuration loading or validation fails
  class ConfigurationError < Error; end
end
