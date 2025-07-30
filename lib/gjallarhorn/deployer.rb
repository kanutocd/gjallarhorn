# frozen_string_literal: true

require "logger"
require_relative "configuration"
require_relative "adapter/base"
require_relative "adapter/aws"
require_relative "deployment/strategy"
require_relative "deployment/zero_downtime"
require_relative "deployment/basic"
require_relative "deployment/legacy"
require_relative "proxy/manager"
require_relative "proxy/nginx_manager"
require_relative "proxy/traefik_manager"
require_relative "proxy/kamal_proxy_manager"
require_relative "history"

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
    # Default configuration file path
    DEFAULT_CONFIG_FILE = "config/deploy.yml"
    
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
    def initialize(config_file = DEFAULT_CONFIG_FILE)
      @configuration = Configuration.new(config_file)
      @logger = Logger.new($stdout)
      @history = History.new
    end

    # Deploy a container image to the specified environment
    #
    # @param environment [String] Target environment name (e.g., 'production', 'staging')
    # @param image [String] Container image tag to deploy (e.g., 'myapp:v1.2.3')
    # @param strategy [String] Deployment strategy to use ('zero_downtime', 'rolling', 'basic')
    # @raise [DeploymentError] If the deployment fails or provider is not supported
    # @return [void]
    def deploy(environment, image, strategy: "zero_downtime")
      # Record deployment start
      @history.record_deployment(
        environment: environment,
        image: image,
        status: "started",
        strategy: strategy
      )

      adapter = create_adapter(environment)
      deployment_strategy = create_deployment_strategy(strategy, adapter, environment)

      @logger.info "Deploying #{image} to #{environment} using #{adapter.class.name} with #{strategy} strategy"

      deployment_strategy.deploy(
        image: image,
        environment: environment,
        services: @configuration.services_for(environment)
      )

      @logger.info "Deployment completed successfully"

      # Record successful deployment
      @history.record_deployment(
        environment: environment,
        image: image,
        status: "success",
        strategy: strategy
      )
    rescue StandardError => e
      # Record failed deployment
      @history.record_deployment(
        environment: environment,
        image: image,
        status: "failed",
        strategy: strategy,
        error: e.message
      )
      raise
    end

    # Deploy with specific strategy (convenience method)
    #
    # @param environment [String] Target environment name
    # @param image [String] Container image tag to deploy
    # @param strategy [String] Deployment strategy to use
    # @return [void]
    def deploy_with_strategy(environment, image, strategy)
      deploy(environment, image, strategy: strategy)
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
      # Record rollback start
      @history.record_deployment(
        environment: environment,
        image: version,
        status: "started",
        strategy: "rollback"
      )

      adapter = create_adapter(environment)
      adapter.rollback(version: version)

      # Record successful rollback
      @history.record_deployment(
        environment: environment,
        image: version,
        status: "success",
        strategy: "rollback"
      )
    rescue StandardError => e
      # Record failed rollback
      @history.record_deployment(
        environment: environment,
        image: version,
        status: "failed",
        strategy: "rollback",
        error: e.message
      )
      raise
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

    # Create a deployment strategy instance
    #
    # @param strategy_name [String] Strategy name ('zero_downtime', 'rolling', 'basic')
    # @param adapter [Adapter::Base] Adapter instance
    # @param environment [String] Target environment name
    # @raise [DeploymentError] If the strategy is not supported
    # @return [Deployment::Strategy] Deployment strategy instance
    # @api private
    def create_deployment_strategy(strategy_name, adapter, environment)
      proxy_manager = create_proxy_manager(environment) if strategy_name == "zero_downtime"

      case strategy_name
      when "zero_downtime"
        Deployment::ZeroDowntime.new(adapter, proxy_manager, @logger)
      when "basic"
        Deployment::Basic.new(adapter, proxy_manager, @logger)
      when "legacy"
        Deployment::Legacy.new(adapter, proxy_manager, @logger)
      else
        raise DeploymentError, "Deployment strategy '#{strategy_name}' not yet implemented"
      end
    end

    # Create a proxy manager instance for zero-downtime deployments
    #
    # @param environment [String] Target environment name
    # @return [Proxy::Manager, nil] Proxy manager instance or nil if not configured
    # @api private
    def create_proxy_manager(environment)
      env_config = @configuration.environment(environment)
      proxy_config = env_config["proxy"]

      return nil unless proxy_config

      Proxy::Manager.create(proxy_config.transform_keys(&:to_sym), @logger)
    rescue StandardError => e
      @logger.warn "Failed to create proxy manager: #{e.message}"
      nil
    end
  end

  # Raised when deployment operations fail
  class DeploymentError < Error; end
end
