# frozen_string_literal: true

require "yaml"
require "logger"

# Base adapter interface
module Gjallarhorn
  module Adapters
    class Base
      attr_reader :config, :logger

      def initialize(config)
        @config = config
        @logger = Logger.new($stdout)
      end

      # Core deployment interface
      def deploy(image:, environment:, services: [])
        raise NotImplementedError, "Subclasses must implement deploy"
      end

      def rollback(version:)
        raise NotImplementedError, "Subclasses must implement rollback"
      end

      def status
        raise NotImplementedError, "Subclasses must implement status"
      end

      def health_check(service:)
        raise NotImplementedError, "Subclasses must implement health_check"
      end

      def scale(service:, replicas:)
        raise NotImplementedError, "Subclasses must implement scale"
      end

      def logs(service:, lines: 100)
        raise NotImplementedError, "Subclasses must implement logs"
      end

      protected

      def wait_for_health(service, timeout = 300)
        start_time = Time.now
        loop do
          return true if health_check(service: service)

          raise "Health check timeout for #{service}" if Time.now - start_time > timeout

          sleep 5
        end
      end
    end
  end
end
