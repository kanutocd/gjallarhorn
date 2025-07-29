# frozen_string_literal: true

require "yaml"

module Bifrost
  class Configuration
    attr_reader :config_file, :data

    def initialize(config_file = "deploy.yml")
      @config_file = config_file
      load_configuration
    end

    def environment(name)
      env_config = @data[name.to_s]
      raise ConfigurationError, "Environment '#{name}' not found in #{config_file}" unless env_config

      env_config
    end

    def environments
      @data.keys
    end

    def provider_for(environment)
      env_config = environment(environment)
      env_config["provider"]
    end

    def services_for(environment)
      env_config = environment(environment)
      env_config["services"] || []
    end

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
      raise ConfigurationError, "Environment '#{env_name}' is not a hash" unless env_config.is_a?(Hash)

      unless env_config["provider"]
        raise ConfigurationError,
              "Environment '#{env_name}' missing required 'provider' field"
      end

      valid_providers = %w[aws gcp azure docker kubernetes]
      provider = env_config["provider"]
      return if valid_providers.include?(provider)

      raise ConfigurationError,
            "Invalid provider '#{provider}' for environment '#{env_name}'. Must be one of: #{valid_providers.join(", ")}"
    end
  end

  class ConfigurationError < Error; end
end
