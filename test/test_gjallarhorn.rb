# frozen_string_literal: true

require "test_helper"

class TestGjallarhorn < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Gjallarhorn::VERSION
  end

  def test_version_is_string
    assert_instance_of String, ::Gjallarhorn::VERSION
  end

  def test_version_follows_semver_pattern
    # Check that version follows semantic versioning pattern
    assert_match(/\A\d+\.\d+\.\d+/, ::Gjallarhorn::VERSION)
  end

  def test_version_constant_access
    # Test that version can be accessed through module
    assert_equal Gjallarhorn::VERSION, ::Gjallarhorn::VERSION
  end

  def test_error_class_exists
    assert_kind_of Class, Gjallarhorn::Error
    assert Gjallarhorn::Error < StandardError
  end

  def test_configuration_error_exists
    assert_kind_of Class, Gjallarhorn::ConfigurationError
    assert Gjallarhorn::ConfigurationError < Gjallarhorn::Error
  end

  def test_deployment_error_exists
    assert_kind_of Class, Gjallarhorn::DeploymentError
    assert Gjallarhorn::DeploymentError < Gjallarhorn::Error
  end
end
