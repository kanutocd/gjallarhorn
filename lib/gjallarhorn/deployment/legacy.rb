# frozen_string_literal: true

require_relative "strategy"

module Gjallarhorn
  module Deployment
    # Legacy deployment strategy
    #
    # Maintains backward compatibility with the original deployment interface
    # by calling the adapter's deploy method directly. This is used for
    # testing and for adapters that haven't been updated to the new
    # container management interface.
    #
    # @since 0.1.0
    class Legacy < Strategy
      # Deploy services using legacy adapter interface
      #
      # @param image [String] Container image to deploy
      # @param environment [String] Target environment
      # @param services [Array<Hash>] Services to deploy
      # @return [void]
      def deploy(image:, environment:, services:)
        @logger.info "Using legacy deployment interface"

        @adapter.deploy(
          image: image,
          environment: environment,
          services: services
        )
      end

      # Check if strategy supports zero-downtime deployments
      #
      # @return [Boolean] Always false for legacy strategy
      def zero_downtime?
        false
      end
    end
  end
end
