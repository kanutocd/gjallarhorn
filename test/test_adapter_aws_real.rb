# frozen_string_literal: true

require "test_helper"

# Test that loads the real AWS adapter but stubs the AWS SDK
class TestRealAWSAdapter < Minitest::Test
  def setup
    @config = {
      region: "us-west-2",
      environment: "production"
    }

    # Stub the AWS SDK dependencies before requiring the adapter
    @aws_module = Module.new
    ssm_module = Module.new
    ec2_module = Module.new

    # Create mock client classes that return mock instances
    @mock_ssm_client = Class.new do
      def initialize(**_args); end

      def send_command(**_args)
        response_mock = Struct.new(:command)
        command_mock = Struct.new(:command_id)
        response_mock.new(command_mock.new("cmd-123"))
      end

      def wait_until(_symbol, **_args)
        yield Struct.new(:max_attempts, :delay).new(nil, nil)
      end
    end

    @mock_ec2_client = Class.new do
      def initialize(**_args); end

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

    ssm_module.const_set(:Client, @mock_ssm_client)
    ec2_module.const_set(:Client, @mock_ec2_client)
    @aws_module.const_set(:SSM, ssm_module)
    @aws_module.const_set(:EC2, ec2_module)

    # Stub the constant before requiring
    Object.const_set(:Aws, @aws_module) unless Object.const_defined?(:Aws)
  end

  def teardown
    # Clean up the constant if we set it
    Object.send(:remove_const, :Aws) if Object.const_defined?(:Aws)
  end

  def test_aws_adapter_loads_and_initializes
    require "gjallarhorn/adapter/aws"

    adapter = Gjallarhorn::Adapter::AWSAdapter.new(@config)
    assert_equal @config, adapter.config
    assert_instance_of Logger, adapter.logger
  end

  def test_aws_adapter_deploy_method
    require "gjallarhorn/adapter/aws"

    adapter = Gjallarhorn::Adapter::AWSAdapter.new(@config)
    services = [{ name: "web", ports: ["80:8080"], env: { "RAILS_ENV" => "production" } }]

    # Should not raise an error
    adapter.deploy(
      image: "myapp:v1.0.0",
      environment: "production",
      services: services
    )
    assert true
  end

  def test_aws_adapter_status_method
    require "gjallarhorn/adapter/aws"

    adapter = Gjallarhorn::Adapter::AWSAdapter.new(@config)
    result = adapter.status

    assert_instance_of Array, result
    # Result should have instance information
    result.each do |item|
      assert item.key?(:instance)
      assert item.key?(:status)
    end
  end

  def test_aws_adapter_rollback_method
    require "gjallarhorn/adapter/aws"

    adapter = Gjallarhorn::Adapter::AWSAdapter.new(@config)
    # Should not raise an error (placeholder implementation)
    adapter.rollback(version: "v1.0.0")
    assert true
  end

  def test_aws_adapter_health_check_method
    require "gjallarhorn/adapter/aws"

    adapter = Gjallarhorn::Adapter::AWSAdapter.new(@config)
    result = adapter.health_check(service: "web")

    # Simplified implementation should return true
    assert result
  end

  def test_aws_adapter_inherited_methods
    require "gjallarhorn/adapter/aws"

    adapter = Gjallarhorn::Adapter::AWSAdapter.new(@config)

    # Test inherited methods that should raise NotImplementedError
    error = assert_raises(NotImplementedError) do
      adapter.scale(service: "web", replicas: 3)
    end
    assert_match(/Subclasses must implement scale/, error.message)

    error = assert_raises(NotImplementedError) do
      adapter.logs(service: "web", lines: 100)
    end
    assert_match(/Subclasses must implement logs/, error.message)
  end
end
