# frozen_string_literal: true

require "thor"
require_relative "deployer"
require_relative "configuration"
require_relative "history"

module Gjallarhorn
  # Command-line interface for Gjallarhorn deployment operations
  #
  # The CLI class provides a Thor-based command-line interface for all deployment
  # operations including deploy, status checks, rollbacks, and configuration management.
  # All methods include comprehensive error handling and user-friendly output.
  #
  # @example Deploy to production
  #   gjallarhorn deploy production myapp:v1.2.3
  #
  # @example Check status with custom config
  #   gjallarhorn status staging --config staging-deploy.yml
  #
  # @example Rollback to previous version
  #   gjallarhorn rollback production v1.2.2
  #
  # @since 0.1.0
  class CLI < Thor
    # Default configuration file path
    DEFAULT_CONFIG_FILE = "config/deploy.yml"

    desc "deploy ENVIRONMENT IMAGE", "Deploy an image to the specified environment"
    option :config, aliases: "-c", default: DEFAULT_CONFIG_FILE, desc: "Configuration file path"
    # Deploy a container image to the specified environment
    #
    # @param environment [String] Target environment name
    # @param image [String] Container image tag to deploy
    def deploy(environment, image)
      deployer = Deployer.new(options[:config])
      deployer.deploy(environment, image)
    rescue StandardError => e
      puts "Deployment failed: #{e.message}"
      exit 1
    end

    desc "status ENVIRONMENT", "Check deployment status for an environment"
    option :config, aliases: "-c", default: DEFAULT_CONFIG_FILE, desc: "Configuration file path"
    # Check the deployment status for services in an environment
    #
    # @param environment [String] Target environment name
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
    option :config, aliases: "-c", default: DEFAULT_CONFIG_FILE, desc: "Configuration file path"
    # Rollback services in an environment to a previous version
    #
    # @param environment [String] Target environment name
    # @param version [String] Version to rollback to
    def rollback(environment, version)
      deployer = Deployer.new(options[:config])
      deployer.rollback(environment, version)
    rescue StandardError => e
      puts "Rollback failed: #{e.message}"
      exit 1
    end

    desc "config", "Show current configuration"
    option :config, aliases: "-c", default: DEFAULT_CONFIG_FILE, desc: "Configuration file path"
    # Display the current configuration in YAML format
    def config
      configuration = Configuration.new(options[:config])
      puts configuration.to_yaml
    rescue StandardError => e
      puts "Configuration error: #{e.message}"
      exit 1
    end

    desc "history ENVIRONMENT", "Show deployment history for an environment"
    option :config, aliases: "-c", default: DEFAULT_CONFIG_FILE, desc: "Configuration file path"
    option :limit, aliases: "-l", type: :numeric, default: 20, desc: "Maximum number of records to show"
    # Display deployment history for the specified environment
    #
    # @param environment [String] Target environment name
    def history(environment)
      history_manager = History.new
      records = history_manager.get_history(environment: environment, limit: options[:limit])

      if records.empty?
        puts "No deployment history found for #{environment}"
        return
      end

      puts "Deployment history for #{environment}:"
      puts "=" * 60

      records.each do |record|
        display_deployment_record(record)
      end

      # Show statistics
      stats = history_manager.statistics(environment: environment)
      puts "Statistics:"
      puts "  Total deployments: #{stats[:total_deployments]}"
      puts "  Success rate: #{stats[:success_rate]}% (#{stats[:successful_deployments]}/#{stats[:total_deployments]})"
    rescue StandardError => e
      puts "Failed to retrieve history: #{e.message}"
      exit 1
    end

    desc "version", "Show Gjallarhorn version"
    # Display the current Gjallarhorn version
    def version
      puts Gjallarhorn::VERSION
    end

    private

    # Display a single deployment record with formatting
    #
    # @param record [Hash] Deployment record
    # @return [void]
    def display_deployment_record(record)
      timestamp = Time.parse(record["timestamp"]).strftime("%Y-%m-%d %H:%M:%S UTC")
      status_indicator = case record["status"]
                         when "success" then "✅"
                         when "failed" then "❌"
                         else "🔄"
                         end

      puts "#{status_indicator} #{timestamp} - #{record["image"]}"
      puts "   Status: #{record["status"]}"
      puts "   Strategy: #{record["strategy"]}" if record["strategy"]
      puts "   Error: #{record["error"]}" if record["error"]
      puts
    end
  end
end
