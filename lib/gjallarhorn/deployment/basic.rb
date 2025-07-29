# frozen_string_literal: true

require_relative "strategy"

module Gjallarhorn
  module Deployment
    # Basic deployment strategy
    #
    # Implements a simple deployment strategy that stops old containers
    # and starts new ones without zero-downtime guarantees. This is the
    # fallback strategy when zero-downtime features are not needed.
    #
    # @since 0.1.0
    class Basic < Strategy
      # Deploy services using basic strategy
      #
      # @param image [String] Container image to deploy
      # @param environment [String] Target environment
      # @param services [Array<Hash>] Services to deploy
      # @return [void]
      def deploy(image:, environment:, services:)
        @logger.info "Starting basic deployment of #{image} to #{environment}"

        services.each do |service|
          @logger.info "Deploying service: #{service[:name]}"
          deploy_service_basic(service, image, environment)
        end

        @logger.info "Basic deployment completed successfully"
      end

      # Check if strategy supports zero-downtime deployments
      #
      # @return [Boolean] Always false for basic strategy
      def zero_downtime?
        false
      end

      private

      # Deploy a single service using basic strategy
      #
      # @param service [Hash] Service configuration
      # @param image [String] Container image to deploy
      # @param environment [String] Target environment
      # @return [void]
      def deploy_service_basic(service, image, environment)
        service_name = service[:name]

        # Step 1: Stop existing containers
        @logger.info "Stopping existing containers for #{service_name}..."
        stop_existing_containers(service_name)

        # Step 2: Start new container
        new_container = start_new_container(service, image, environment)
        @logger.info "Started new container: #{new_container[:name]} (#{new_container[:id]})"

        # Step 3: Wait for container to be running
        wait_for_container_running(new_container)

        # Step 4: Optional health check
        if service[:healthcheck]
          @logger.info "Waiting for health check to pass..."
          wait_for_container_health(new_container, service[:healthcheck])
        end

        @logger.info "Service #{service_name} deployed successfully"
      end

      # Stop all existing containers for a service
      #
      # @param service_name [String] Service name
      # @return [void]
      def stop_existing_containers(service_name)
        current_containers = @adapter.get_running_containers(service_name)

        current_containers.each do |container|
          @logger.info "Stopping container: #{container[:name]} (#{container[:id]})"
          @adapter.stop_container(container[:id], graceful: true)
          @adapter.remove_container(container[:id])
        end
      rescue StandardError => e
        @logger.warn "Failed to stop some existing containers: #{e.message}"
        # Continue with deployment even if cleanup fails
      end

      # Start a new container for the service
      #
      # @param service [Hash] Service configuration
      # @param image [String] Container image
      # @param environment [String] Target environment
      # @return [Hash] New container information
      def start_new_container(service, image, environment)
        container_name = generate_container_name(service[:name])

        container_config = {
          name: container_name,
          image: image,
          ports: service[:ports] || [],
          env: build_environment_variables(service, environment),
          volumes: service[:volumes] || [],
          command: service[:cmd],
          labels: build_container_labels(service, environment),
          restart_policy: service[:restart_policy] || "unless-stopped"
        }

        @adapter.start_container(container_config)
      end

      # Build environment variables for container
      #
      # @param service [Hash] Service configuration
      # @param environment [String] Target environment
      # @return [Hash] Environment variables
      def build_environment_variables(service, environment)
        env_vars = {
          "GJALLARHORN_SERVICE" => service[:name],
          "GJALLARHORN_ENVIRONMENT" => environment,
          "GJALLARHORN_DEPLOYED_AT" => Time.now.utc.iso8601
        }

        # Add service-specific environment variables
        env_vars.merge!(service[:env]) if service[:env]

        env_vars
      end

      # Build container labels for identification and management
      #
      # @param service [Hash] Service configuration
      # @param environment [String] Target environment
      # @return [Hash] Container labels
      def build_container_labels(service, environment)
        {
          "gjallarhorn.service" => service[:name],
          "gjallarhorn.environment" => environment,
          "gjallarhorn.role" => service[:role] || "web",
          "gjallarhorn.deployed_at" => Time.now.utc.iso8601,
          "gjallarhorn.strategy" => "basic"
        }
      end

      # Wait for container to be in running state
      #
      # @param container [Hash] Container information
      # @param timeout [Integer] Timeout in seconds
      # @return [Boolean] True when container is running
      def wait_for_container_running(container, timeout = 60)
        start_time = Time.now

        loop do
          status = @adapter.get_container_status(container[:id])

          if status == "running"
            @logger.info "Container #{container[:name]} is running"
            return true
          end

          elapsed = Time.now - start_time
          if elapsed >= timeout
            raise DeploymentError,
                  "Container #{container[:name]} failed to start within #{timeout}s (status: #{status})"
          end

          @logger.debug "Container #{container[:name]} status: #{status}, waiting..."
          sleep 2
        end
      end
    end
  end
end
