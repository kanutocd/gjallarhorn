# frozen_string_literal: true

require "test_helper"

class TestAdapterBase < Minitest::Test
  def setup
    @config = { "test" => "config" }
    @adapter = Bifrost::Adapter::Base.new(@config)
  end

  def test_initializes_with_config_and_logger
    assert_equal @config, @adapter.config
    assert_kind_of Logger, @adapter.logger
  end

  def test_deploy_raises_not_implemented_error
    error = assert_raises(NotImplementedError) do
      @adapter.deploy(image: "test", environment: "test")
    end

    assert_equal "Subclasses must implement deploy", error.message
  end

  def test_rollback_raises_not_implemented_error
    error = assert_raises(NotImplementedError) do
      @adapter.rollback(version: "v1.0.0")
    end

    assert_equal "Subclasses must implement rollback", error.message
  end

  def test_status_raises_not_implemented_error
    error = assert_raises(NotImplementedError) do
      @adapter.status
    end

    assert_equal "Subclasses must implement status", error.message
  end

  def test_health_check_raises_not_implemented_error
    error = assert_raises(NotImplementedError) do
      @adapter.health_check(service: "web")
    end

    assert_equal "Subclasses must implement health_check", error.message
  end

  def test_scale_raises_not_implemented_error
    error = assert_raises(NotImplementedError) do
      @adapter.scale(service: "web", replicas: 3)
    end

    assert_equal "Subclasses must implement scale", error.message
  end

  def test_logs_raises_not_implemented_error
    error = assert_raises(NotImplementedError) do
      @adapter.logs(service: "web")
    end

    assert_equal "Subclasses must implement logs", error.message
  end

  def test_wait_for_health_returns_true_when_healthy
    # Mock health_check to return true immediately
    @adapter.stub(:health_check, true) do
      result = @adapter.send(:wait_for_health, "web")
      assert_equal true, result
    end
  end

  def test_wait_for_health_raises_timeout_error
    # Mock health_check to always return false and Time.now to simulate timeout
    start_time = Time.now
    times_called = 0

    time_mock = proc do
      times_called += 1
      # First call returns start time, second call returns time past timeout
      times_called == 1 ? start_time : start_time + 301
    end

    Time.stub(:now, time_mock) do
      @adapter.stub(:health_check, false) do
        error = assert_raises(RuntimeError) do
          @adapter.send(:wait_for_health, "web", 300)
        end

        assert_match(/Health check timeout for web/, error.message)
      end
    end
  end
end
