# frozen_string_literal: true

require_relative "manager"

module Gjallarhorn
  module Proxy
    # Traefik proxy manager for zero-downtime deployments
    #
    # This is a placeholder implementation for Traefik support.
    # Full implementation will be added in a future release.
    #
    # @since 0.1.0
    class TraefikManager < Manager
      # Switch traffic from old containers to new container
      #
      # @param service_name [String] Service name
      # @param from_containers [Array<Hash>] Containers to switch traffic from
      # @param to_container [Hash] Container to switch traffic to
      # @return [void]
      def switch_traffic(service_name:, from_containers:, to_container:)
        raise NotImplementedError, "Traefik proxy support not yet implemented"
      end

      # Get traefik proxy status
      #
      # @return [Hash] Traefik status information
      def status
        {
          type: "traefik",
          status: "not_implemented",
          upstreams: []
        }
      end
    end
  end
end
