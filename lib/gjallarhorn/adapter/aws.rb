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
        @ssm = Aws::SSM::Client.new(region: config[:region])
        @ec2 = Aws::EC2::Client.new(region: config[:region])
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
        instances = get_instances_by_tags(config[:environment])
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

      private

      def get_instances_by_tags(environment)
        resp = @ec2.describe_instances(
          filters: [
            { name: "tag:Environment", values: [environment] },
            { name: "tag:Role", values: %w[web app] },
            { name: "instance-state-name", values: ["running"] }
          ]
        )

        resp.reservations.flat_map(&:instances).map(&:instance_id)
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

      def wait_for_command_completion(command_id, _instances)
        @ssm.wait_until(:command_executed, command_id: command_id) do |w|
          w.max_attempts = 60
          w.delay = 5
        end
      end
    end
  end
end
