# frozen_string_literal: true

require "logger"
require_relative "configuration"
require_relative "adapter/base"
require_relative "adapter/aws"

# Main deployment orchestrator that handles deployments across different cloud providers
#
# The Deployer class acts as the central coordinator for all deployment operations,
# managing configuration loading, adapter selection, and deployment execution across
# different cloud environments.
#
# @example Basic deployment
#   deployer = Gjallarhorn::Deployer.new('config/deploy.yml')
#   deployer.deploy('production', 'myapp:v1.2.3')
#
# @example Check service status
#   status = deployer.status('staging')
#   puts status.inspect
#
# @example Rollback to previous version
#   deployer.rollback('production', 'v1.2.2')
#
# @since 0.1.0
module Gjallarhorn
  # Main deployment orchestrator class
  class Deployer
    # Mapping of provider names to their corresponding adapter classes
    # @api private
    ADAPTERS = {
      "aws" => Adapter::AWSAdapter,
      "gcp" => nil, # TODO: Implement in Phase 2
      "azure" => nil, # TODO: Implement in Phase 2
      "docker" => nil, # TODO: Implement in Phase 2
      "kubernetes" => nil # TODO: Implement in Phase 3
    }.freeze

    # @return [Configuration] The loaded deployment configuration
    attr_reader :configuration

    # @return [Logger] Logger instance for deployment operations
    attr_reader :logger

    # Initialize a new Deployer instance
    #
    # @param config_file [String] Path to the YAML configuration file
    # @raise [ConfigurationError] If the configuration file is invalid
    def initialize(config_file = "deploy.yml")
      @configuration = Configuration.new(config_file)
      @logger = Logger.new($stdout)
    end

    # Deploy a container image to the specified environment
    #
    # @param environment [String] Target environment name (e.g., 'production', 'staging')
    # @param image [String] Container image tag to deploy (e.g., 'myapp:v1.2.3')
    # @raise [DeploymentError] If the deployment fails or provider is not supported
    # @return [void]
    def deploy(environment, image)
      adapter = create_adapter(environment)
      @logger.info "Deploying #{image} to #{environment} using #{adapter.class.name}"

      adapter.deploy(
        image: image,
        environment: environment,
        services: @configuration.services_for(environment)
      )

      @logger.info "Deployment completed successfully"
    end

    # Get the current status of services in the specified environment
    #
    # @param environment [String] Target environment name
    # @raise [DeploymentError] If the provider is not supported
    # @return [Hash] Status information for all services in the environment
    def status(environment)
      adapter = create_adapter(environment)
      adapter.status
    end

    # Rollback services in the environment to a previous version
    #
    # @param environment [String] Target environment name
    # @param version [String] Version to rollback to (e.g., 'v1.2.2')
    # @raise [DeploymentError] If the rollback fails or provider is not supported
    # @return [void]
    def rollback(environment, version)
      adapter = create_adapter(environment)
      adapter.rollback(version: version)
    end

    private

    # Create an adapter instance for the specified environment
    #
    # @param environment [String] Target environment name
    # @raise [DeploymentError] If the provider is not supported
    # @return [Adapter::Base] Configured adapter instance
    # @api private
    def create_adapter(environment)
      env_config = @configuration.environment(environment)
      provider = env_config["provider"]
      adapter_class = ADAPTERS[provider]

      raise DeploymentError, "Provider '#{provider}' not yet implemented" unless adapter_class

      adapter_class.new(env_config)
    end
  end

  # Raised when deployment operations fail
  class DeploymentError < Error; end
end
