# frozen_string_literal: true

require "yaml"
require "logger"

# Base adapter interface for cloud provider implementations
#
# The Base class defines the common interface that all cloud provider adapters
# must implement. It provides the foundation for deploying, managing, and monitoring
# containerized applications across different cloud platforms.
#
# @abstract Subclass and override {#deploy}, {#rollback}, {#status}, {#health_check},
#   {#scale}, and {#logs} to implement a cloud provider adapter.
#
# @example Implementing a custom adapter
#   class MyCloudAdapter < Gjallarhorn::Adapter::Base
#     def deploy(image:, environment:, services: [])
#       # Implementation specific to MyCloud
#     end
#   end
#
# @since 0.1.0
module Gjallarhorn
  module Adapter
    # Abstract base class for all cloud provider adapters
    class Base
      # @return [Hash] Configuration hash for this adapter
      attr_reader :config

      # @return [Logger] Logger instance for adapter operations
      attr_reader :logger

      # Initialize a new adapter instance
      #
      # @param config [Hash] Configuration hash containing provider-specific settings
      def initialize(config)
        @config = config
        @logger = Logger.new($stdout)
      end

      # Deploy a container image with the specified services
      #
      # @param image [String] Container image tag to deploy
      # @param environment [String] Target environment name
      # @param services [Array<Hash>] List of service configurations to deploy
      # @abstract Subclasses must implement this method
      # @raise [NotImplementedError] If not implemented by subclass
      # @return [void]
      def deploy(image:, environment:, services: [])
        raise NotImplementedError, "Subclasses must implement deploy"
      end

      # Rollback services to a previous version
      #
      # @param version [String] Version to rollback to
      # @abstract Subclasses must implement this method
      # @raise [NotImplementedError] If not implemented by subclass
      # @return [void]
      def rollback(version:)
        raise NotImplementedError, "Subclasses must implement rollback"
      end

      # Get the current status of all services
      #
      # @abstract Subclasses must implement this method
      # @raise [NotImplementedError] If not implemented by subclass
      # @return [Array<String>] Status information for all services
      def status
        raise NotImplementedError, "Subclasses must implement status"
      end

      # Check the health status of a specific service
      #
      # @param service [String] Service name to check
      # @abstract Subclasses must implement this method
      # @raise [NotImplementedError] If not implemented by subclass
      # @return [Boolean] True if service is healthy, false otherwise
      def health_check(service:)
        raise NotImplementedError, "Subclasses must implement health_check"
      end

      # Scale a service to the specified number of replicas
      #
      # @param service [String] Service name to scale
      # @param replicas [Integer] Target number of replicas
      # @abstract Subclasses must implement this method
      # @raise [NotImplementedError] If not implemented by subclass
      # @return [void]
      def scale(service:, replicas:)
        raise NotImplementedError, "Subclasses must implement scale"
      end

      # Retrieve logs from a specific service
      #
      # @param service [String] Service name to get logs from
      # @param lines [Integer] Number of log lines to retrieve (default: 100)
      # @abstract Subclasses must implement this method
      # @raise [NotImplementedError] If not implemented by subclass
      # @return [String] Service logs
      def logs(service:, lines: 100)
        raise NotImplementedError, "Subclasses must implement logs"
      end

      protected

      # Wait for a service to become healthy with timeout
      #
      # @param service [String] Service name to wait for
      # @param timeout [Integer] Maximum time to wait in seconds (default: 300)
      # @raise [RuntimeError] If the service doesn't become healthy within timeout
      # @return [Boolean] True when service becomes healthy
      # @api private
      def wait_for_health(service, timeout = 300)
        start_time = Time.now
        loop do
          return true if health_check(service: service)

          raise "Health check timeout for #{service}" if Time.now - start_time > timeout

          sleep 5
        end
      end
    end
  end
end
