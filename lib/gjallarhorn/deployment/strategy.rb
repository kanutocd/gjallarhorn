# frozen_string_literal: true

require "securerandom"

module Gjallarhorn
  module Deployment
    # Base class for deployment strategies
    #
    # Defines the interface that all deployment strategies must implement.
    # Each strategy handles the specifics of how containers are deployed,
    # updated, and managed during the deployment process.
    #
    # @abstract Subclass and override deployment methods
    # @since 0.1.0
    class Strategy
      attr_reader :adapter, :proxy_manager, :logger

      # Initialize a deployment strategy
      #
      # @param adapter [Adapter::Base] The cloud adapter to use
      # @param proxy_manager [Proxy::Manager] The proxy manager for traffic switching
      # @param logger [Logger] Logger instance
      def initialize(adapter, proxy_manager, logger = nil)
        @adapter = adapter
        @proxy_manager = proxy_manager
        @logger = logger || Logger.new($stdout)
      end

      # Deploy services using this strategy
      #
      # @param image [String] Container image to deploy
      # @param environment [String] Target environment
      # @param services [Array<Hash>] Services to deploy
      # @abstract Subclasses must implement this method
      # @raise [NotImplementedError] If not implemented by subclass
      # @return [void]
      def deploy(image:, environment:, services:)
        raise NotImplementedError, "Subclasses must implement deploy method"
      end

      # Check if strategy supports zero-downtime deployments
      #
      # @return [Boolean] True if strategy supports zero-downtime
      def zero_downtime?
        false
      end

      # Get strategy name
      #
      # @return [String] Strategy name
      def name
        self.class.name.split("::").last.downcase
      end

      protected

      # Wait for container to become healthy
      #
      # @param container [Hash] Container information
      # @param healthcheck [Hash] Health check configuration
      # @param timeout [Integer] Timeout in seconds
      # @raise [HealthCheckTimeoutError] If health check times out
      # @return [Boolean] True when container is healthy
      def wait_for_container_health(container, healthcheck, timeout = 300)
        max_attempts = healthcheck[:max_attempts] || 30
        interval = healthcheck[:interval] || 3
        start_time = Time.now

        attempts = 0

        loop do
          if container_healthy?(container, healthcheck)
            @logger.info "Container #{container[:name]} passed health check after #{attempts} attempts"
            return true
          end

          attempts += 1
          elapsed = Time.now - start_time

          if attempts >= max_attempts || elapsed >= timeout
            raise HealthCheckTimeoutError,
                  "Container #{container[:name]} failed health check after #{attempts} attempts (#{elapsed.round(1)}s)"
          end

          @logger.debug "Health check attempt #{attempts}/#{max_attempts} failed, retrying in #{interval}s..."
          sleep interval
        end
      end

      # Check if container is healthy
      #
      # @param container [Hash] Container information
      # @param healthcheck [Hash] Health check configuration
      # @return [Boolean] True if container is healthy
      def container_healthy?(container, healthcheck)
        case healthcheck[:type]
        when "http", nil
          http_health_check(container, healthcheck)
        when "command"
          command_health_check(container, healthcheck)
        when "docker"
          docker_health_check(container)
        else
          @logger.warn "Unknown health check type: #{healthcheck[:type]}, defaulting to HTTP"
          http_health_check(container, healthcheck)
        end
      end

      # Perform HTTP health check
      #
      # @param container [Hash] Container information
      # @param healthcheck [Hash] Health check configuration
      # @return [Boolean] True if HTTP check passes
      def http_health_check(container, healthcheck)
        require "net/http"
        require "uri"

        path = healthcheck[:path] || "/health"
        port = healthcheck[:port] || 3000
        expected_status = healthcheck[:expected_status] || [200, 204]
        expected_status = [expected_status] unless expected_status.is_a?(Array)

        # Try to get container IP or use localhost if running locally
        host = container[:ip] || container[:host] || "localhost"
        url = "http://#{host}:#{port}#{path}"

        begin
          uri = URI(url)
          response = Net::HTTP.get_response(uri)
          status_ok = expected_status.include?(response.code.to_i)

          @logger.debug "Health check #{url} returned #{response.code}" if status_ok
          status_ok
        rescue StandardError => e
          @logger.debug "Health check failed: #{e.message}"
          false
        end
      end

      # Perform command-based health check
      #
      # @param container [Hash] Container information
      # @param healthcheck [Hash] Health check configuration
      # @return [Boolean] True if command succeeds
      def command_health_check(container, healthcheck)
        command = healthcheck[:command] || healthcheck[:cmd]
        return false unless command

        begin
          @adapter.execute_in_container(container[:id], command)
          true
        rescue StandardError => e
          @logger.debug "Command health check failed: #{e.message}"
          false
        end
      end

      # Perform Docker health check
      #
      # @param container [Hash] Container information
      # @return [Boolean] True if Docker reports container as healthy
      def docker_health_check(container)
        @adapter.get_container_health(container[:id])
      rescue StandardError => e
        @logger.debug "Docker health check failed: #{e.message}"
        false
      end

      # Generate unique container name with timestamp
      #
      # @param service_name [String] Base service name
      # @return [String] Unique container name
      def generate_container_name(service_name)
        timestamp = Time.now.strftime("%Y%m%d-%H%M%S")
        "#{service_name}-#{timestamp}-#{SecureRandom.hex(4)}"
      end

      # Generate version suffix for tracking
      #
      # @return [String] Version suffix
      def generate_version_suffix
        Time.now.strftime("%Y%m%d-%H%M%S")
      end
    end

    # Raised when health checks timeout
    class HealthCheckTimeoutError < Error; end
  end
end
