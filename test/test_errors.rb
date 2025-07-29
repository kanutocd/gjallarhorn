# frozen_string_literal: true

require "test_helper"

class TestErrors < Minitest::Test
  def test_gjallarhorn_error_is_standard_error
    error = Gjallarhorn::Error.new("test message")
    assert_instance_of Gjallarhorn::Error, error
    assert_kind_of StandardError, error
    assert_equal "test message", error.message
  end

  def test_configuration_error_inherits_from_gjallarhorn_error
    error = Gjallarhorn::ConfigurationError.new("config error")
    assert_instance_of Gjallarhorn::ConfigurationError, error
    assert_kind_of Gjallarhorn::Error, error
    assert_equal "config error", error.message
  end

  def test_deployment_error_inherits_from_gjallarhorn_error
    error = Gjallarhorn::DeploymentError.new("deployment error")
    assert_instance_of Gjallarhorn::DeploymentError, error
    assert_kind_of Gjallarhorn::Error, error
    assert_equal "deployment error", error.message
  end
end
