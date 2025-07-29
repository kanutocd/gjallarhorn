# frozen_string_literal: true

require "thor"
require_relative "deployer"
require_relative "configuration"

module Gjallarhorn
  class CLI < Thor
    desc "deploy ENVIRONMENT IMAGE", "Deploy an image to the specified environment"
    option :config, aliases: "-c", default: "deploy.yml", desc: "Configuration file path"
    def deploy(environment, image)
      deployer = Deployer.new(options[:config])
      deployer.deploy(environment, image)
    rescue StandardError => e
      puts "Deployment failed: #{e.message}"
      exit 1
    end

    desc "status ENVIRONMENT", "Check deployment status for an environment"
    option :config, aliases: "-c", default: "deploy.yml", desc: "Configuration file path"
    def status(environment)
      deployer = Deployer.new(options[:config])
      result = deployer.status(environment)

      puts "Status for #{environment}:"
      result.each do |status_info|
        puts "  #{status_info}"
      end
    rescue StandardError => e
      puts "Status check failed: #{e.message}"
      exit 1
    end

    desc "rollback ENVIRONMENT VERSION", "Rollback to a previous version"
    option :config, aliases: "-c", default: "deploy.yml", desc: "Configuration file path"
    def rollback(environment, version)
      deployer = Deployer.new(options[:config])
      deployer.rollback(environment, version)
    rescue StandardError => e
      puts "Rollback failed: #{e.message}"
      exit 1
    end

    desc "config", "Show current configuration"
    option :config, aliases: "-c", default: "deploy.yml", desc: "Configuration file path"
    def config
      configuration = Configuration.new(options[:config])
      puts configuration.to_yaml
    rescue StandardError => e
      puts "Configuration error: #{e.message}"
      exit 1
    end

    desc "version", "Show Gjallarhorn version"
    def version
      puts Gjallarhorn::VERSION
    end
  end
end
