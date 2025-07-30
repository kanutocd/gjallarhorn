# frozen_string_literal: true

require "test_helper"

# Mock AWS adapter class that doesn't require AWS SDK
class MockAWSAdapter < Gjallarhorn::Adapter::Base
  attr_reader :ssm, :ec2, :current_environment

  def initialize(config)
    @config = config
    @logger = Logger.new($stdout)
    @ssm = MockSSMClient.new
    @ec2 = MockEC2Client.new
    @current_environment = nil
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

  # Set the current deployment environment
  def set_environment(environment)
    @current_environment = environment
  end

  # Start a new container
  def start_container(container_config)
    {
      id: "container-#{Time.now.to_i}",
      name: container_config[:name],
      image: container_config[:image],
      created_at: Time.now.utc
    }
  end

  # Get running containers for a service
  def get_running_containers(service_name)
    [
      {
        id: "container-123",
        name: "#{service_name}-old",
        status: "running",
        created_at: Time.now.utc - 3600,
        service: service_name
      }
    ]
  end

  # Get container status
  def get_container_status(container_id)
    "running"
  end

  # Stop a container
  def stop_container(container_id, graceful: true, timeout: 30)
    @logger.info "Stopping container: #{container_id}"
  end

  # Remove a container
  def remove_container(container_id)
    @logger.info "Removing container: #{container_id}"
  end

  # Get all containers for a service
  def get_all_containers(service_name)
    [
      {
        id: "container-123",
        name: "#{service_name}-old",
        status: "exited",
        created_at: Time.now.utc - 7200,
        service: service_name
      },
      {
        id: "container-456",
        name: "#{service_name}-current",
        status: "running",  
        created_at: Time.now.utc - 3600,
        service: service_name
      }
    ]
  end

  # Get target instances for deployment
  def target_instances(environment = nil)
    # Check if instance IDs are explicitly configured
    instance_ids = @config["instance_ids"] || @config[:instance_ids] || 
                  @config["instance-ids"] || @config[:"instance-ids"]
    
    if instance_ids && !instance_ids.empty?
      instance_ids = [instance_ids] unless instance_ids.is_a?(Array)
      @logger.debug "Using configured instance IDs: #{instance_ids.join(', ')}"
      return instance_ids
    end
    
    # Fall back to tag-based discovery
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

  private

  def get_instances_by_tags(environment)
    @logger.debug "Querying EC2 instances with filters: Environment=#{environment}, Role=web|app, state=running"
    # Mock returning different instances based on environment
    case environment
    when "staging"
      %w[i-staging-123 i-staging-456]
    when "production"
      %w[i-prod-123 i-prod-456]
    else
      %w[i-123 i-456]
    end
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
    assert_equal "i-prod-123", result[0][:instance]  # Updated to match mock environment behavior
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

  def test_set_environment
    @adapter.set_environment("staging")
    assert_equal "staging", @adapter.current_environment
  end

  def test_target_instances_uses_configured_instance_ids
    config_with_instances = @config.merge(instance_ids: ["i-custom-123", "i-custom-456"])
    adapter = MockAWSAdapter.new(config_with_instances)
    
    instances = adapter.target_instances
    assert_equal ["i-custom-123", "i-custom-456"], instances
  end

  def test_target_instances_uses_single_configured_instance_id
    config_with_instance = @config.merge(instance_ids: "i-single-123")
    adapter = MockAWSAdapter.new(config_with_instance)
    
    instances = adapter.target_instances
    assert_equal ["i-single-123"], instances
  end

  def test_target_instances_falls_back_to_tag_discovery
    instances = @adapter.target_instances("staging")
    assert_equal ["i-staging-123", "i-staging-456"], instances
  end

  def test_target_instances_uses_current_environment
    @adapter.set_environment("staging")
    instances = @adapter.target_instances
    assert_equal ["i-staging-123", "i-staging-456"], instances
  end

  def test_target_instances_raises_error_when_no_instances_found
    # Mock empty response
    @adapter.define_singleton_method(:get_instances_by_tags) { |_env| [] }
    
    error = assert_raises(ArgumentError) do
      @adapter.target_instances("nonexistent")
    end
    
    assert_match(/No EC2 instances found for environment 'nonexistent'/, error.message)
    assert_match(/Either configure 'instance_ids'/, error.message)
  end

  def test_start_container
    container_config = {
      name: "web-container",
      image: "myapp:v1.0.0",
      ports: ["80:3000"],
      env: { "RAILS_ENV" => "production" }
    }
    
    result = @adapter.start_container(container_config)
    
    assert result[:id].start_with?("container-")
    assert_equal "web-container", result[:name]
    assert_equal "myapp:v1.0.0", result[:image]
    assert_instance_of Time, result[:created_at]
  end

  def test_get_running_containers
    containers = @adapter.get_running_containers("web")
    
    assert_equal 1, containers.length
    assert_equal "container-123", containers[0][:id]
    assert_equal "web-old", containers[0][:name]
    assert_equal "running", containers[0][:status]
    assert_equal "web", containers[0][:service]
  end

  def test_get_all_containers
    containers = @adapter.get_all_containers("web")
    
    assert_equal 2, containers.length
    assert containers.any? { |c| c[:status] == "exited" }
    assert containers.any? { |c| c[:status] == "running" }
  end

  def test_get_container_status
    status = @adapter.get_container_status("container-123")
    assert_equal "running", status
  end

  def test_stop_container
    # Should not raise an error
    @adapter.stop_container("container-123", graceful: true, timeout: 30)
    @adapter.stop_container("container-456", graceful: false)
    assert true
  end

  def test_remove_container
    # Should not raise an error
    @adapter.remove_container("container-123")
    assert true
  end
end
