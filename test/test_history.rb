# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

class TestHistory < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
    @history = Gjallarhorn::History.new(history_dir: @temp_dir)
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)
  end

  def test_record_and_retrieve_deployment
    @history.record_deployment(
      environment: "production",
      image: "myapp:v1.0.0",
      status: "success",
      strategy: "zero_downtime"
    )

    records = @history.get_history(environment: "production")
    assert_equal 1, records.length

    record = records.first
    assert_equal "production", record["environment"]
    assert_equal "myapp:v1.0.0", record["image"]
    assert_equal "success", record["status"]
    assert_equal "zero_downtime", record["strategy"]
    assert record["timestamp"]
  end

  def test_record_failed_deployment_with_error
    @history.record_deployment(
      environment: "staging",
      image: "myapp:v1.1.0",
      status: "failed",
      strategy: "zero_downtime",
      error: "Health check failed"
    )

    records = @history.get_history(environment: "staging")
    record = records.first

    assert_equal "failed", record["status"]
    assert_equal "Health check failed", record["error"]
  end

  def test_filter_history_by_environment
    @history.record_deployment(
      environment: "production",
      image: "myapp:v1.0.0",
      status: "success"
    )

    @history.record_deployment(
      environment: "staging",
      image: "myapp:v1.1.0",
      status: "success"
    )

    prod_records = @history.get_history(environment: "production")
    staging_records = @history.get_history(environment: "staging")

    assert_equal 1, prod_records.length
    assert_equal 1, staging_records.length
    assert_equal "production", prod_records.first["environment"]
    assert_equal "staging", staging_records.first["environment"]
  end

  def test_limit_history_records
    5.times do |i|
      @history.record_deployment(
        environment: "production",
        image: "myapp:v1.#{i}.0",
        status: "success"
      )
    end

    records = @history.get_history(environment: "production", limit: 3)
    assert_equal 3, records.length
  end

  def test_last_successful_deployment
    @history.record_deployment(
      environment: "production",
      image: "myapp:v1.0.0",
      status: "success"
    )

    @history.record_deployment(
      environment: "production",
      image: "myapp:v1.1.0",
      status: "failed"
    )

    @history.record_deployment(
      environment: "production",
      image: "myapp:v1.2.0",
      status: "success"
    )

    last_success = @history.last_successful_deployment("production")
    assert_equal "myapp:v1.2.0", last_success["image"]
    assert_equal "success", last_success["status"]
  end

  def test_available_versions_for_rollback
    @history.record_deployment(
      environment: "production",
      image: "myapp:v1.0.0",
      status: "success"
    )

    @history.record_deployment(
      environment: "production",
      image: "myapp:v1.1.0",
      status: "failed"
    )

    @history.record_deployment(
      environment: "production",
      image: "myapp:v1.2.0",
      status: "success"
    )

    versions = @history.available_versions("production")
    assert_equal 2, versions.length
    assert_includes versions, "myapp:v1.2.0"
    assert_includes versions, "myapp:v1.0.0"
    refute_includes versions, "myapp:v1.1.0" # Failed deployment shouldn't be available
  end

  def test_deployment_statistics
    @history.record_deployment(
      environment: "production",
      image: "myapp:v1.0.0",
      status: "success"
    )

    @history.record_deployment(
      environment: "production",
      image: "myapp:v1.1.0",
      status: "failed"
    )

    @history.record_deployment(
      environment: "production",
      image: "myapp:v1.2.0",
      status: "success"
    )

    stats = @history.statistics(environment: "production")
    assert_equal 3, stats[:total_deployments]
    assert_equal 2, stats[:successful_deployments]
    assert_equal 1, stats[:failed_deployments]
    assert_equal 66.67, stats[:success_rate]
  end

  def test_clear_history_for_environment
    @history.record_deployment(
      environment: "production",
      image: "myapp:v1.0.0",
      status: "success"
    )

    @history.record_deployment(
      environment: "staging",
      image: "myapp:v1.1.0",
      status: "success"
    )

    @history.clear_history(environment: "production")

    prod_records = @history.get_history(environment: "production")
    staging_records = @history.get_history(environment: "staging")

    assert_empty prod_records
    assert_equal 1, staging_records.length
  end

  def test_handles_empty_history_file
    records = @history.get_history
    assert_empty records

    stats = @history.statistics
    assert_equal 0, stats[:total_deployments]
    assert_equal 0, stats[:success_rate]
  end
end