# frozen_string_literal: true

require "logger"
require_relative "configuration"
require_relative "adapters/base"
require_relative "adapters/aws"

# Main Deployer Class
module Gjallarhorn
  class Deployer
    ADAPTERS = {
      "aws" => Adapters::AWSAdapter,
      "gcp" => nil, # TODO: Implement in Phase 2
      "azure" => nil, # TODO: Implement in Phase 2
      "docker" => nil, # TODO: Implement in Phase 2
      "kubernetes" => nil # TODO: Implement in Phase 3
    }.freeze

    attr_reader :configuration, :logger

    def initialize(config_file = "deploy.yml")
      @configuration = Configuration.new(config_file)
      @logger = Logger.new($stdout)
    end

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

    def status(environment)
      adapter = create_adapter(environment)
      adapter.status
    end

    def rollback(environment, version)
      adapter = create_adapter(environment)
      adapter.rollback(version: version)
    end

    private

    def create_adapter(environment)
      env_config = @configuration.environment(environment)
      provider = env_config["provider"]
      adapter_class = ADAPTERS[provider]

      raise DeploymentError, "Provider '#{provider}' not yet implemented" unless adapter_class

      adapter_class.new(env_config)
    end
  end

  class DeploymentError < Error; end
end
