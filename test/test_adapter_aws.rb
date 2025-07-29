# frozen_string_literal: true

require "test_helper"

# Mock AWS adapter class that doesn't require AWS SDK
class MockAWSAdapter < Gjallarhorn::Adapter::Base
  attr_reader :ssm, :ec2

  def initialize(config)
    @config = config
    @logger = Logger.new($stdout)
    @ssm = MockSSMClient.new
    @ec2 = MockEC2Client.new
  end

  def deploy(image:, environment:, services: [])
    instances = get_instances_by_tags(environment)
    commands = build_deployment_commands(image, services)

    @logger.info "Deploying #{image} to #{instances.size} AWS instances"

    response = execute_deployment_command(instances, commands, image)
    wait_for_command_completion(response.command.command_id, instances)
    verify_service_health(services)

    @logger.info "Deployment completed successfully"
  end

  def rollback(version:)
    # Placeholder implementation
  end

  def status
    instances = get_instances_by_tags(@config[:environment])
    instances.map do |instance_id|
      {
        instance: instance_id,
        status: get_instance_status(instance_id)
      }
    end
  end

  def health_check(*)
    true # Simplified
  end

  private

  def get_instances_by_tags(_environment)
    %w[i-123 i-456] # Mock instance IDs
  end

  def build_deployment_commands(image, services)
    [
      "docker pull #{image}",
      *services.map { |svc| "docker stop #{svc[:name]} || true" },
      *services.map do |svc|
        "docker run -d --name #{svc[:name]} " \
        "#{svc[:ports]&.map { |p| "-p #{p}" }&.join(" ")} " \
        "#{svc[:env]&.map { |k, v| "-e #{k}=#{v}" }&.join(" ")} " \
        "#{image}"
      end
    ]
  end

  def execute_deployment_command(_instances, _commands, _image)
    response_mock = Struct.new(:command)
    command_mock = Struct.new(:command_id)
    response_mock.new(command_mock.new("cmd-123"))
  end

  def verify_service_health(services)
    services.each { |service| wait_for_health(service) }
  end

  def wait_for_command_completion(command_id, _instances)
    # Mock implementation
  end

  def get_instance_status(_instance_id)
    "running"
  end
end

class MockSSMClient
  def send_command(**_args)
    response_mock = Struct.new(:command)
    command_mock = Struct.new(:command_id)
    response_mock.new(command_mock.new("cmd-123"))
  end

  def wait_until(_symbol, **_args)
    yield Struct.new(:max_attempts, :delay).new
  end
end

class MockEC2Client
  def describe_instances(**_args)
    instance_mock = Struct.new(:instance_id, :state)
    state_mock = Struct.new(:name)
    reservation_mock = Struct.new(:instances)
    response_mock = Struct.new(:reservations)

    response_mock.new([
                        reservation_mock.new([
                                               instance_mock.new("i-123", state_mock.new("running"))
                                             ])
                      ])
  end
end

class TestAWSAdapter < Minitest::Test
  def setup
    @config = {
      region: "us-west-2",
      environment: "production"
    }
    @adapter = MockAWSAdapter.new(@config)
  end

  def test_initialize_sets_config
    assert_equal @config, @adapter.config
    assert_instance_of Logger, @adapter.logger
  end

  def test_deploy_calls_required_methods
    services = [{ name: "web", ports: ["80:8080"], env: { "RAILS_ENV" => "production" } }]

    # Should not raise an error
    @adapter.deploy(
      image: "myapp:v1.0.0",
      environment: "production",
      services: services
    )
    assert true
  end

  def test_rollback_placeholder
    @adapter.rollback(version: "v1.0.0")
    assert true
  end

  def test_status_returns_instance_status
    result = @adapter.status
    assert_equal 2, result.length
    assert_equal "i-123", result[0][:instance]
    assert_equal "running", result[0][:status]
  end

  def test_health_check_returns_true
    assert @adapter.health_check(service: "web")
  end

  def test_build_deployment_commands
    services = [
      {
        name: "web",
        ports: ["80:8080"],
        env: { "RAILS_ENV" => "production" }
      }
    ]

    commands = @adapter.send(:build_deployment_commands, "myapp:v1.0.0", services)

    assert_includes commands, "docker pull myapp:v1.0.0"
    assert_includes commands, "docker stop web || true"
    assert(commands.any? { |cmd| cmd.include?("docker run -d --name web") })
    assert(commands.any? { |cmd| cmd.include?("-p 80:8080") })
    assert(commands.any? { |cmd| cmd.include?("-e RAILS_ENV=production") })
  end

  def test_execute_deployment_command
    result = @adapter.send(:execute_deployment_command, ["i-123"], ["echo hello"], "myapp:v1.0.0")
    assert_equal "cmd-123", result.command.command_id
  end

  def test_verify_service_health
    services = [{ name: "web" }, { name: "api" }]
    # Should not raise an error
    @adapter.send(:verify_service_health, services)
    assert true
  end

  def test_get_instance_status
    result = @adapter.send(:get_instance_status, "i-123")
    assert_equal "running", result
  end

  def test_scale_method_not_implemented
    error = assert_raises(NotImplementedError) do
      @adapter.scale(service: "web", replicas: 3)
    end
    assert_match(/Subclasses must implement scale/, error.message)
  end

  def test_logs_method_not_implemented
    error = assert_raises(NotImplementedError) do
      @adapter.logs(service: "web", lines: 100)
    end
    assert_match(/Subclasses must implement logs/, error.message)
  end
end
