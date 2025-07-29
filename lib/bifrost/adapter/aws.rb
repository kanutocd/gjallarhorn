# frozen_string_literal: true

# AWS SSM Adapter
module Bifrost
  module Adapter
    class AWSAdapter < Base
      def initialize(config)
        super
        require "aws-sdk-ssm"
        require "aws-sdk-ec2"
        @ssm = Aws::SSM::Client.new(region: config[:region])
        @ec2 = Aws::EC2::Client.new(region: config[:region])
      end

      def deploy(image:, environment:, services: [])
        instances = get_instances_by_tags(environment)

        commands = build_deployment_commands(image, services)

        logger.info "Deploying #{image} to #{instances.size} AWS instances"

        response = @ssm.send_command(
          instance_ids: instances,
          document_name: "AWS-RunShellScript",
          parameters: {
            "commands" => commands,
            "executionTimeout" => ["3600"]
          },
          comment: "Deploy #{image} via Universal Deployer"
        )

        wait_for_command_completion(response.command.command_id, instances)

        # Verify health across all instances
        services.each do |service|
          wait_for_health(service)
        end

        logger.info "Deployment completed successfully"
      end

      def rollback(version:)
        # Similar implementation for rollback
      end

      def status
        instances = get_instances_by_tags(config[:environment])
        instances.map do |instance_id|
          {
            instance: instance_id,
            status: get_instance_status(instance_id)
          }
        end
      end

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

      def wait_for_command_completion(command_id, _instances)
        @ssm.wait_until(:command_executed, command_id: command_id) do |w|
          w.max_attempts = 60
          w.delay = 5
        end
      end
    end
  end
end
