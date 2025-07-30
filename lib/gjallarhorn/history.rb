# frozen_string_literal: true

require "json"
require "fileutils"
require "time"

module Gjallarhorn
  # Deployment history tracking and management
  #
  # Handles tracking of deployment history in a local JSON file,
  # providing functionality to record deployments and query history.
  #
  # @since 0.1.0
  class History
    # Default directory for storing history files
    DEFAULT_HISTORY_DIR = File.expand_path("~/.gjallarhorn")
    
    # Default filename for history storage
    DEFAULT_HISTORY_FILE = "history.json"

    # Initialize history manager
    #
    # @param history_dir [String] Directory to store history files
    def initialize(history_dir: DEFAULT_HISTORY_DIR)
      @history_dir = history_dir
      @history_file = File.join(@history_dir, DEFAULT_HISTORY_FILE)
      ensure_history_directory
    end

    # Record a deployment attempt
    #
    # @param environment [String] Environment name
    # @param image [String] Container image deployed
    # @param status [String] Deployment status ('success', 'failed', 'started')
    # @param strategy [String] Deployment strategy used (optional)
    # @param error [String] Error message if deployment failed (optional)
    # @return [void]
    def record_deployment(environment:, image:, status:, strategy: nil, error: nil)
      deployment_record = {
        timestamp: Time.now.utc.iso8601,
        environment: environment,
        image: image,
        status: status,
        strategy: strategy,
        error: error
      }.compact

      history_data = load_history
      history_data << deployment_record

      # Keep only the last 100 deployments to prevent file from growing too large
      history_data = history_data.last(100) if history_data.length > 100

      save_history(history_data)
    end

    # Get deployment history for a specific environment
    #
    # @param environment [String] Environment name (optional, returns all if nil)
    # @param limit [Integer] Maximum number of records to return
    # @return [Array<Hash>] Array of deployment records
    def get_history(environment: nil, limit: 20)
      history_data = load_history

      # Filter by environment if specified
      if environment
        history_data = history_data.select { |record| record["environment"] == environment }
      end

      # Sort by timestamp (most recent first) and limit results
      history_data.sort_by { |record| record["timestamp"] }.reverse.first(limit)
    end

    # Get the last successful deployment for an environment
    #
    # @param environment [String] Environment name
    # @return [Hash, nil] Last successful deployment record or nil if none found
    def last_successful_deployment(environment)
      history_data = load_history
      
      history_data
        .select { |record| record["environment"] == environment && record["status"] == "success" }
        .sort_by { |record| record["timestamp"] }
        .last
    end

    # Get available versions for rollback
    #
    # @param environment [String] Environment name
    # @param limit [Integer] Maximum number of versions to return
    # @return [Array<String>] Array of available image tags
    def available_versions(environment, limit: 10)
      successful_deployments = get_history(environment: environment, limit: 50)
        .select { |record| record["status"] == "success" }
        .uniq { |record| record["image"] }

      successful_deployments.first(limit).map { |record| record["image"] }
    end

    # Clear history for a specific environment or all environments
    #
    # @param environment [String] Environment name (optional, clears all if nil)
    # @return [void]
    def clear_history(environment: nil)
      if environment
        history_data = load_history.reject { |record| record["environment"] == environment }
        save_history(history_data)
      else
        save_history([])
      end
    end

    # Get deployment statistics
    #
    # @param environment [String] Environment name (optional)
    # @return [Hash] Statistics about deployments
    def statistics(environment: nil)
      history_data = load_history
      
      if environment
        history_data = history_data.select { |record| record["environment"] == environment }
      end

      total = history_data.length
      successful = history_data.count { |record| record["status"] == "success" }
      failed = history_data.count { |record| record["status"] == "failed" }

      {
        total_deployments: total,
        successful_deployments: successful,
        failed_deployments: failed,
        success_rate: total > 0 ? (successful.to_f / total * 100).round(2) : 0
      }
    end

    private

    # Ensure the history directory exists
    #
    # @return [void]
    def ensure_history_directory
      FileUtils.mkdir_p(@history_dir) unless Dir.exist?(@history_dir)
    end

    # Load history data from file
    #
    # @return [Array<Hash>] Array of deployment records
    def load_history
      return [] unless File.exist?(@history_file)

      JSON.parse(File.read(@history_file))
    rescue JSON::ParserError, Errno::ENOENT
      []
    end

    # Save history data to file
    #
    # @param history_data [Array<Hash>] Array of deployment records
    # @return [void]
    def save_history(history_data)
      File.write(@history_file, JSON.pretty_generate(history_data))
    end
  end
end