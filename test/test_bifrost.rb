# frozen_string_literal: true

require "test_helper"

class TestBifrost < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Bifrost::VERSION
  end

  def test_error_class_exists
    assert_kind_of Class, Bifrost::Error
    assert Bifrost::Error < StandardError
  end

  def test_configuration_error_exists
    assert_kind_of Class, Bifrost::ConfigurationError
    assert Bifrost::ConfigurationError < Bifrost::Error
  end

  def test_deployment_error_exists
    assert_kind_of Class, Bifrost::DeploymentError
    assert Bifrost::DeploymentError < Bifrost::Error
  end
end
