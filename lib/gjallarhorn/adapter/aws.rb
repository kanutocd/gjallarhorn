# frozen_string_literal: true

# AWS SSM deployment adapter for managing containerized applications
#
# The AWSAdapter uses AWS Systems Manager (SSM) to deploy and manage Docker containers
# on EC2 instances without requiring SSH access. It provides secure, API-first deployments
# by executing commands remotely through AWS SSM.
#
# @example Configuration
#   production:
#     provider: aws
#     region: us-west-2
#     services:
#       - name: web
#         ports: ["80:8080"]
#         env:
#           RAILS_ENV: production
#
# @since 0.1.0
module Gjallarhorn
  module Adapter
    # AWS Systems Manager adapter for container deployments
    class AWSAdapter < Base
      # Initialize AWS adapter with SSM and EC2 clients
      #
      # @param config [Hash] Configuration containing AWS region and other settings
      def initialize(config)
        super
        require "aws-sdk-ssm"
        require "aws-sdk-ec2"
        
        # Handle both string and symbol keys for region
        region = config["region"] || config[:region]
        raise ArgumentError, "AWS region is required in configuration" unless region
        
        @ssm = Aws::SSM::Client.new(region: region)
        @ec2 = Aws::EC2::Client.new(region: region)
        @current_environment = nil
      end

      # Deploy container images to AWS EC2 instances via SSM
      #
      # @param image [String] Docker image to deploy
      # @param environment [String] Target environment name
      # @param services [Array<Hash>] Service configurations to deploy
      # @return [void]
      def deploy(image:, environment:, services: [])
        instances = get_instances_by_tags(environment)
        commands = build_deployment_commands(image, services)

        logger.info "Deploying #{image} to #{instances.size} AWS instances"

        response = execute_deployment_command(instances, commands, image)
        wait_for_command_completion(response.command.command_id, instances)
        verify_service_health(services)

        logger.info "Deployment completed successfully"
      end

      # Rollback to a previous version (placeholder implementation)
      #
      # @param version [String] Version to rollback to
      # @return [void]
      # @todo Implement rollback functionality
      def rollback(version:)
        # Similar implementation for rollback
      end

      # Get status of all instances in the environment
      #
      # @return [Array<Hash>] Instance status information
      def status
        environment = config["environment"] || config[:environment] || "production"
        instances = get_instances_by_tags(environment)
        instances.map do |instance_id|
          {
            instance: instance_id,
            status: get_instance_status(instance_id)
          }
        end
      end

      # Check health of a service (simplified implementation)
      #
      # @param service [String] Service name to check
      # @return [Boolean] Always returns true (simplified)
      # @todo Implement actual health check via SSM
      def health_check(*)
        # Implement health check via SSM command
        true # Simplified
      end

      # Set the current deployment environment
      #
      # @param environment [String] Environment name
      # @return [void]
      def set_environment(environment)
        @current_environment = environment
      end

      # Start a new container with enhanced configuration
      #
      # @param container_config [Hash] Container configuration
      # @return [Hash] Container information
      def start_container(container_config)
        config = extract_container_config(container_config)
        docker_cmd = build_docker_run_command(config)

        @logger.info "Starting container: #{config[:name]}"
        @logger.debug "Docker command: #{docker_cmd}"

        container_id = execute_container_start(docker_cmd)
        finalize_container_setup(container_id, config)
      end

      # Get running containers for a service
      #
      # @param service_name [String] Service name
      # @return [Array<Hash>] Array of container information
      def get_running_containers(service_name)
        # List containers with service label/name pattern
        cmd = [
          "docker ps",
          "--filter label=gjallarhorn.service=#{service_name}",
          "--format '{{.ID}}:{{.Names}}:{{.Status}}:{{.CreatedAt}}'"
        ].join(" ")

        output = execute_ssm_command_with_response(cmd)
        parse_container_list(output, service_name)
      end

      private

      def get_instances_by_tags(environment)
        @logger.debug "Querying EC2 instances with filters: Environment=#{environment}, Role=web|app, state=running"
        
        resp = @ec2.describe_instances(
          filters: [
            { name: "tag:Environment", values: [environment] },
            { name: "tag:Role", values: %w[web app] },
            { name: "instance-state-name", values: ["running"] }
          ]
        )

        instances = resp.reservations.flat_map(&:instances)
        @logger.debug "Found #{instances.length} instances matching filters"
        
        instances.each do |instance|
          tags_info = begin
            if instance.respond_to?(:tags) && instance.tags
              instance.tags.map { |t| "#{t.key}=#{t.value}" }.join(', ')
            else
              "N/A"
            end
          rescue StandardError
            "N/A"
          end
          @logger.debug "Instance: #{instance.instance_id}, State: #{instance.state.name}, Tags: #{tags_info}"
        end

        instance_ids = instances.map(&:instance_id)
        @logger.debug "Returning instance IDs: #{instance_ids.join(', ')}" if instance_ids.any?
        
        instance_ids
      end

      def build_deployment_commands(image, services)
        [
          "docker pull #{image}",
          *services.map { |svc| "docker stop #{svc[:name]} || true" },
          *services.map do |svc|
            "docker run -d --name #{svc[:name]} " \
            "#{svc[:ports].map { |p| "-p #{p}" }.join(" ")} " \
            "#{svc[:env].map { |k, v| "-e #{k}=#{v}" }.join(" ")} " \
            "#{image}"
          end
        ]
      end

      def execute_deployment_command(instances, commands, image)
        @ssm.send_command(
          instance_ids: instances,
          document_name: "AWS-RunShellScript",
          parameters: {
            "commands" => commands,
            "executionTimeout" => ["3600"]
          },
          comment: "Deploy #{image} via Gjallarhorn"
        )
      end

      def verify_service_health(services)
        services.each { |service| wait_for_health(service) }
      end

      def wait_for_command_completion(command_id, instances)
        # Use the first instance for command completion check
        instance_id = instances.is_a?(Array) ? instances.first : instances
        @logger.debug "wait_for_command_completion: Using instance #{instance_id} for command #{command_id}"
        
        @ssm.wait_until(:command_executed, command_id: command_id, instance_id: instance_id) do |w|
          w.max_attempts = 60
          w.delay = 5
        end
      end

      def get_instance_status(instance_id)
        resp = @ec2.describe_instances(instance_ids: [instance_id])
        instance = resp.reservations.first&.instances&.first
        instance&.state&.name || "unknown"
      rescue StandardError
        "unknown"
      end

      # Get all containers for a service (including stopped)
      #
      # @param service_name [String] Service name
      # @return [Array<Hash>] Array of all container information
      def get_all_containers(service_name)
        cmd = [
          "docker ps -a",
          "--filter label=gjallarhorn.service=#{service_name}",
          "--format '{{.ID}}:{{.Names}}:{{.Status}}:{{.CreatedAt}}'"
        ].join(" ")

        output = execute_ssm_command_with_response(cmd)
        parse_container_list(output, service_name)
      end

      # Stop a container
      #
      # @param container_id [String] Container ID
      # @param graceful [Boolean] Whether to stop gracefully
      # @param timeout [Integer] Timeout for graceful stop
      # @return [void]
      def stop_container(container_id, graceful: true, timeout: 30)
        if graceful
          @logger.info "Gracefully stopping container: #{container_id}"
          execute_ssm_command("docker stop --time #{timeout} #{container_id}")
        else
          @logger.info "Force stopping container: #{container_id}"
          execute_ssm_command("docker kill #{container_id}")
        end
      end

      # Remove a container
      #
      # @param container_id [String] Container ID
      # @return [void]
      def remove_container(container_id)
        @logger.info "Removing container: #{container_id}"
        execute_ssm_command("docker rm #{container_id}")
      end

      # Execute command in a running container
      #
      # @param container_id [String] Container ID
      # @param command [String] Command to execute
      # @return [String] Command output
      def execute_in_container(container_id, command)
        docker_cmd = "docker exec #{container_id} #{command}"
        execute_ssm_command_with_response(docker_cmd)
      end

      # Get container health status
      #
      # @param container_id [String] Container ID
      # @return [Boolean] True if container is healthy
      def get_container_health(container_id)
        health_output = execute_ssm_command_with_response(
          "docker inspect #{container_id} --format '{{.State.Health.Status}}'"
        )

        health_status = health_output.strip.downcase
        health_status == "healthy"
      rescue StandardError => e
        @logger.debug "Health check failed for #{container_id}: #{e.message}"
        # If no health check is configured, check if container is running
        get_container_status(container_id) == "running"
      end

      # Get container status
      #
      # @param container_id [String] Container ID
      # @return [String] Container status
      def get_container_status(container_id)
        status_output = execute_ssm_command_with_response(
          "docker inspect #{container_id} --format '{{.State.Status}}'"
        )
        status_output.strip.downcase
      rescue StandardError
        "unknown"
      end

      # Get detailed container information
      #
      # @param container_id [String] Container ID
      # @return [Hash] Container information
      def get_container_info(container_id)
        # Get container IP address
        ip_cmd = "docker inspect #{container_id} --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'"
        ip_address = execute_ssm_command_with_response(ip_cmd).strip

        # Get container port mappings
        ports_cmd = "docker port #{container_id}"
        ports_output = execute_ssm_command_with_response(ports_cmd)

        {
          id: container_id,
          ip: ip_address.empty? ? nil : ip_address,
          ports: parse_container_ports(ports_output),
          host: target_instances.first # Simplified - use first instance
        }
      rescue StandardError => e
        @logger.warn "Failed to get container info for #{container_id}: #{e.message}"
        {
          id: container_id,
          ip: nil,
          ports: [],
          host: target_instances.first
        }
      end

      # Build Docker run command from configuration
      #
      # @param config [Hash] Container configuration
      # @return [String] Docker run command
      def build_docker_run_command(config)
        cmd_parts = ["docker run -d"]

        # Container name
        cmd_parts << "--name #{config[:name]}"

        # Port mappings
        config[:ports].each do |port|
          cmd_parts << "-p #{port}"
        end

        # Environment variables
        config[:env].each do |key, value|
          cmd_parts << "-e #{key}=#{shell_escape(value)}"
        end

        # Volume mounts
        config[:volumes].each do |volume|
          cmd_parts << "-v #{volume}"
        end

        # Labels
        config[:labels].each do |key, value|
          cmd_parts << "--label #{key}=#{shell_escape(value)}"
        end

        # Restart policy
        cmd_parts << "--restart #{config[:restart_policy]}"

        # Image
        cmd_parts << config[:image]

        # Command (if specified)
        cmd_parts << config[:command] if config[:command]

        cmd_parts.join(" ")
      end

      # Execute SSM command and return response
      #
      # @param command [String] Command to execute
      # @return [String] Command output
      def execute_ssm_command_with_response(command)
        instances = target_instances
        @logger.debug "execute_ssm_command_with_response: Using instances: #{instances.inspect}"
        @logger.debug "execute_ssm_command_with_response: Command: #{command}"
        
        response = @ssm.send_command(
          instance_ids: instances,
          document_name: "AWS-RunShellScript",
          parameters: {
            "commands" => [command],
            "executionTimeout" => ["300"]
          }
        )

        command_id = response.command.command_id
        wait_for_command_completion(command_id, target_instances)

        # Get command output
        get_command_output(command_id)
      end

      # Get command output from SSM
      #
      # @param command_id [String] SSM command ID
      # @return [String] Command output
      def get_command_output(command_id)
        instances = target_instances
        @logger.debug "get_command_output: Using instances: #{instances.inspect}"
        @logger.debug "get_command_output: First instance: #{instances.first.inspect}"

        # Get output from first instance (simplified)
        result = @ssm.get_command_invocation(
          command_id: command_id,
          instance_id: instances.first
        )

        if result.status_details == "Success"
          result.standard_output_content || ""
        else
          error_msg = result.standard_error_content || "Command failed"
          raise DeploymentError, "SSM command failed: #{error_msg}"
        end
      end

      # Parse container list output
      #
      # @param output [String] Docker ps output
      # @param service_name [String] Service name for filtering
      # @return [Array<Hash>] Parsed container information
      def parse_container_list(output, service_name)
        containers = []

        output.split("\n").each do |line|
          next if line.strip.empty?

          parts = line.split(":")
          next unless parts.length >= 3

          containers << {
            id: parts[0],
            name: parts[1],
            status: parts[2],
            created_at: parse_container_timestamp(parts[3]),
            service: service_name
          }
        end

        containers
      end

      # Parse container port mappings
      #
      # @param ports_output [String] Docker port command output
      # @return [Array<String>] Port mappings
      def parse_container_ports(ports_output)
        ports = []

        ports_output.split("\n").each do |line|
          next if line.strip.empty?

          # Format: "3000/tcp -> 0.0.0.0:3000"
          next unless line.match(%r{(\d+)/tcp -> [\d.]+:(\d+)})

          container_port = ::Regexp.last_match(1)
          host_port = ::Regexp.last_match(2)
          ports << "#{host_port}:#{container_port}"
        end

        ports
      end

      # Parse container creation timestamp
      #
      # @param timestamp_str [String] Timestamp string from Docker
      # @return [Time] Parsed timestamp
      def parse_container_timestamp(timestamp_str)
        return Time.now.utc unless timestamp_str

        # Docker timestamp format: "2024-01-15 10:30:45 +0000 UTC"
        Time.parse(timestamp_str).utc
      rescue StandardError
        Time.now.utc
      end

      # Wait for container to be running
      #
      # @param container_id [String] Container ID
      # @param timeout [Integer] Timeout in seconds
      # @return [void]
      def wait_for_container_running(container_id, timeout = 60)
        start_time = Time.now

        loop do
          status = get_container_status(container_id)

          if status == "running"
            @logger.info "Container #{container_id} is running"
            return
          elsif status == "exited"
            raise DeploymentError, "Container #{container_id} exited unexpectedly"
          end

          elapsed = Time.now - start_time
          if elapsed >= timeout
            raise DeploymentError, "Container #{container_id} failed to start within #{timeout}s (status: #{status})"
          end

          @logger.debug "Container #{container_id} status: #{status}, waiting..."
          sleep 2
        end
      end

      # Escape shell arguments
      #
      # @param value [String] Value to escape
      # @return [String] Shell-escaped value
      def shell_escape(value)
        "'#{value.to_s.gsub("'", "'\\''")}'"
      end

      # Execute SSM command without returning response (fire and forget)
      #
      # @param command [String] Command to execute
      # @return [void]
      def execute_ssm_command(command)
        instances = target_instances
        @logger.debug "execute_ssm_command: Using instances: #{instances.inspect}"
        @logger.debug "execute_ssm_command: Command: #{command}"
        
        @ssm.send_command(
          instance_ids: instances,
          document_name: "AWS-RunShellScript",
          parameters: {
            "commands" => [command],
            "executionTimeout" => ["300"]
          }
        )
      end

      # Get target instances for the current environment
      #
      # @param environment [String] Environment name (overrides config)
      # @return [Array<String>] Array of instance IDs
      def target_instances(environment = nil)
        # Check if instance IDs are explicitly configured
        instance_ids = @config["instance_ids"] || @config[:instance_ids] || 
                      @config["instance-ids"] || @config[:"instance-ids"]
        
        if instance_ids && !instance_ids.empty?
          # Use explicitly configured instance IDs
          instance_ids = [instance_ids] unless instance_ids.is_a?(Array)
          @logger.debug "Using configured instance IDs: #{instance_ids.join(', ')}"
          return instance_ids
        end
        
        # Fall back to tag-based discovery
        # Use provided environment parameter, current environment, config, or default to production
        env_name = environment || @current_environment || @config["environment"] || @config[:environment] || "production"
        @logger.debug "No instance IDs configured, discovering instances by tags for environment: #{env_name}"
        discovered_instances = get_instances_by_tags(env_name)
        
        if discovered_instances.empty?
          raise ArgumentError, "No EC2 instances found for environment '#{env_name}'. " \
                              "Either configure 'instance_ids' in your deploy.yml or ensure your EC2 " \
                              "instances are tagged with Environment=#{env_name} and Role=web|app"
        end
        
        discovered_instances
      end

      # Extract ECR registries from Docker command
      #
      # @param docker_cmd [String] Docker command
      # @return [Array<Hash>] Array of ECR registry information
      def extract_ecr_registries(docker_cmd)
        registries = []
        
        # Match ECR registry URLs: account.dkr.ecr.region.amazonaws.com
        ecr_pattern = /(\d+)\.dkr\.ecr\.([^.]+)\.amazonaws\.com/
        
        docker_cmd.scan(ecr_pattern) do |account_id, region|
          registry_url = "#{account_id}.dkr.ecr.#{region}.amazonaws.com"
          registries << {
            account_id: account_id,
            region: region,
            registry_url: registry_url
          }
        end
        
        registries.uniq
      end

      # Authenticate with ECR registries
      #
      # @param registries [Array<Hash>] ECR registry information
      # @return [void]
      def authenticate_ecr_registries(registries)
        registries.each do |registry|
          @logger.info "Authenticating with ECR registry: #{registry[:registry_url]}"
          
          login_cmd = "aws ecr get-login-password --region #{registry[:region]} | " \
                     "docker login --username AWS --password-stdin #{registry[:registry_url]}"
          
          begin
            execute_ssm_command_with_response(login_cmd)
            @logger.info "Successfully authenticated with ECR registry: #{registry[:registry_url]}"
          rescue StandardError => e
            @logger.error "Failed to authenticate with ECR registry #{registry[:registry_url]}: #{e.message}"
            raise StandardError, "ECR authentication failed for #{registry[:registry_url]}: #{e.message}"
          end
        end
      end

      # Extract and normalize container configuration
      #
      # @param container_config [Hash] Raw container configuration
      # @return [Hash] Normalized configuration
      def extract_container_config(container_config)
        {
          name: container_config[:name],
          image: container_config[:image],
          ports: container_config[:ports] || [],
          env: container_config[:env] || {},
          volumes: container_config[:volumes] || [],
          command: container_config[:command],
          labels: container_config[:labels] || {},
          restart_policy: container_config[:restart_policy] || "unless-stopped"
        }
      end

      # Execute container start command and return container ID
      #
      # @param docker_cmd [String] Docker run command
      # @return [String] Container ID
      def execute_container_start(docker_cmd)
        # Check if we need ECR authentication
        if docker_cmd.include?('.dkr.ecr.')
          @logger.debug "ECR registry detected, ensuring authentication"
          ecr_registries = extract_ecr_registries(docker_cmd)
          authenticate_ecr_registries(ecr_registries)
        end

        execute_ssm_command_with_response(docker_cmd).strip
      end

      # Finalize container setup after creation
      #
      # @param container_id [String] Container ID
      # @param config [Hash] Container configuration
      # @return [Hash] Container information
      def finalize_container_setup(container_id, config)
        wait_for_container_running(container_id)

        container_info = get_container_info(container_id)
        container_info.merge(
          name: config[:name],
          image: config[:image],
          created_at: Time.now.utc
        )
      end
    end
  end
end
