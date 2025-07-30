# frozen_string_literal: true

require_relative "strategy"

module Gjallarhorn
  module Deployment
    # Zero-downtime deployment strategy
    #
    # Implements zero-downtime deployments by:
    # 1. Starting new containers alongside existing ones
    # 2. Waiting for new containers to pass health checks
    # 3. Switching proxy traffic to new containers
    # 4. Gracefully stopping old containers
    #
    # This ensures continuous service availability during deployments.
    #
    # @since 0.1.0
    class ZeroDowntime < Strategy
      # Deploy services with zero downtime
      #
      # @param image [String] Container image to deploy
      # @param environment [String] Target environment
      # @param services [Array<Hash>] Services to deploy
      # @return [void]
      def deploy(image:, environment:, services:)
        @logger.info "Starting zero-downtime deployment of #{image} to #{environment}"

        # Set the environment on the adapter so it knows which environment we're deploying to
        @adapter.set_environment(environment) if @adapter.respond_to?(:set_environment)

        deployment_results = []

        services.each do |service|
          # Convert string keys to symbols for consistency
          service = service.transform_keys(&:to_sym) if service.is_a?(Hash)
          @logger.info "Deploying service: #{service[:name]}"
          result = deploy_service_zero_downtime(service, image, environment)
          deployment_results << result
        end

        @logger.info "Zero-downtime deployment completed successfully"
        deployment_results
      end

      # Check if strategy supports zero-downtime deployments
      #
      # @return [Boolean] Always true for this strategy
      def zero_downtime?
        true
      end

      private

      # Deploy a single service with zero downtime
      #
      # @param service [Hash] Service configuration
      # @param image [String] Container image to deploy
      # @param environment [String] Target environment
      # @return [Hash] Deployment result
      def deploy_service_zero_downtime(service, image, environment)
        # Ensure service hash uses symbol keys
        service = service.transform_keys(&:to_sym) if service.is_a?(Hash)
        service_name = service[:name]

        # Step 1: Get current running containers
        current_containers = get_current_containers(service_name)
        @logger.info "Found #{current_containers.length} existing containers for #{service_name}"

        # Step 2: Start new container
        new_container = start_new_container(service, image, environment)
        @logger.info "Started new container: #{new_container[:name]} (#{new_container[:id]})"

        # Step 3: Wait for new container to be healthy
        if service[:healthcheck]
          @logger.info "Waiting for health check to pass..."
          wait_for_container_health(new_container, service[:healthcheck])
        else
          @logger.info "No health check configured, waiting for container to be running..."
          wait_for_container_running(new_container)
        end

        # Step 4: Update proxy routing to new container
        if @proxy_manager
          @logger.info "Switching proxy traffic to new container..."
          @proxy_manager.switch_traffic(
            service_name: service_name,
            from_containers: current_containers,
            to_container: new_container
          )
        else
          @logger.warn "No proxy manager configured, skipping traffic switch"
        end

        # Step 5: Gracefully stop old containers
        if current_containers.any?
          @logger.info "Stopping #{current_containers.length} old containers..."
          stop_old_containers(current_containers, service[:drain_timeout] || 30)
        end

        # Step 6: Clean up old containers
        cleanup_old_containers(service_name, new_container[:id])

        {
          service: service_name,
          old_containers: current_containers.map { |c| c[:id] },
          new_container: new_container[:id],
          status: "success"
        }
      rescue StandardError => e
        @logger.error "Failed to deploy #{service_name}: #{e.message}"

        # Cleanup: Remove the new container if deployment failed
        if defined?(new_container) && new_container
          @logger.info "Cleaning up failed deployment container..."
          @adapter.stop_container(new_container[:id], graceful: false)
        end

        raise DeploymentError, "Zero-downtime deployment failed for #{service_name}: #{e.message}"
      end

      # Get currently running containers for a service
      #
      # @param service_name [String] Service name
      # @return [Array<Hash>] Array of container information
      def get_current_containers(service_name)
        @logger.debug "get_current_containers: Calling adapter.get_running_containers for service: #{service_name}"
        @adapter.get_running_containers(service_name)
      rescue StandardError => e
        @logger.warn "Failed to get current containers for #{service_name}: #{e.message}"
        @logger.debug "get_current_containers error backtrace: #{e.backtrace.join("\n")}"
        []
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

        @logger.debug "start_new_container: Calling adapter.start_container with config: #{container_config.inspect}"
        begin
          result = @adapter.start_container(container_config)
          @logger.debug "start_new_container: Result: #{result.inspect}"
          result
        rescue StandardError => e
          @logger.error "start_new_container failed: #{e.message}"
          @logger.debug "start_new_container error backtrace: #{e.backtrace.join("\n")}"
          raise
        end
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
        # Handle both string and symbol keys from YAML
        service_env = service[:env] || service["env"]
        env_vars.merge!(service_env) if service_env

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
          "gjallarhorn.strategy" => "zero_downtime"
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

      # Gracefully stop old containers
      #
      # @param containers [Array<Hash>] Containers to stop
      # @param drain_timeout [Integer] Time to wait for graceful shutdown
      # @return [void]
      def stop_old_containers(containers, drain_timeout = 30)
        containers.each do |container|
          @logger.info "Stopping container: #{container[:name]} (#{container[:id]})"

          begin
            # Give container time to finish current requests
            @adapter.stop_container(container[:id], graceful: true, timeout: drain_timeout)
            @logger.info "Successfully stopped container: #{container[:name]}"
          rescue StandardError => e
            @logger.error "Failed to stop container #{container[:name]}: #{e.message}"
            # Continue with other containers even if one fails
          end
        end
      end

      # Clean up old containers, keeping a configurable number for rollback
      #
      # @param service_name [String] Service name
      # @param exclude_container_id [String] Container ID to exclude from cleanup
      # @param keep_count [Integer] Number of old containers to keep
      # @return [void]
      def cleanup_old_containers(service_name, exclude_container_id, keep_count = 2)
        all_containers = @adapter.get_all_containers(service_name)
        old_containers = all_containers.reject { |c| c[:id] == exclude_container_id }

        # Sort by creation time (newest first) and keep only the specified count
        containers_to_remove = old_containers.sort_by { |c| c[:created_at] }.reverse.drop(keep_count)

        containers_to_remove.each do |container|
          @logger.info "Removing old container: #{container[:name]} (#{container[:id]})"
          @adapter.remove_container(container[:id])
        end

        @logger.info "Cleaned up #{containers_to_remove.length} old containers" if containers_to_remove.any?
      rescue StandardError => e
        @logger.warn "Failed to cleanup old containers: #{e.message}"
        # Don't fail deployment if cleanup fails
      end
    end

    # Raised when deployment operations fail
    class DeploymentError < Error; end
  end
end
