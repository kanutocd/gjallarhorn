# frozen_string_literal: true

module Gjallarhorn
  module Proxy
    # Base proxy manager class
    #
    # Handles traffic routing and switching during deployments.
    # Supports different proxy types (nginx, traefik, kamal-proxy)
    # for zero-downtime deployments.
    #
    # @since 0.1.0
    class Manager
      attr_reader :config, :proxy_type, :logger

      # Initialize proxy manager
      #
      # @param config [Hash] Proxy configuration
      # @param logger [Logger] Logger instance
      def initialize(config, logger = nil)
        @config = config
        @proxy_type = config[:type] || "nginx"
        @logger = logger || Logger.new($stdout)
      end

      # Switch traffic from old containers to new container
      #
      # @param service_name [String] Service name
      # @param from_containers [Array<Hash>] Containers to switch traffic from
      # @param to_container [Hash] Container to switch traffic to
      # @abstract Subclasses should implement this method
      # @return [void]
      def switch_traffic(service_name:, from_containers:, to_container:)
        raise NotImplementedError, "Subclasses must implement switch_traffic"
      end

      # Get proxy status
      #
      # @return [Hash] Proxy status information
      def status
        {
          type: @proxy_type,
          status: "unknown",
          upstreams: []
        }
      end

      # Restart proxy service
      #
      # @return [Boolean] True if restart successful
      def restart
        @logger.info "Restarting #{@proxy_type} proxy..."
        false # Default implementation
      end

      # Check if proxy is healthy
      #
      # @return [Boolean] True if proxy is responding
      def healthy?
        false # Default implementation
      end

      # Create appropriate proxy manager based on configuration
      #
      # @param config [Hash] Proxy configuration
      # @param logger [Logger] Logger instance
      # @return [Manager] Proxy manager instance
      def self.create(config, logger = nil)
        case config[:type]
        when "nginx"
          NginxManager.new(config, logger)
        when "traefik"
          TraefikManager.new(config, logger)
        when "kamal-proxy"
          KamalProxyManager.new(config, logger)
        else
          raise ConfigurationError, "Unsupported proxy type: #{config[:type]}"
        end
      end

      protected

      # Verify that traffic switch was successful
      #
      # @param service_name [String] Service name
      # @param container [Hash] Container that should be receiving traffic
      # @param max_attempts [Integer] Maximum verification attempts
      # @return [Boolean] True if verification successful
      def verify_traffic_switch(service_name, container, max_attempts = 10)
        return true unless @config[:domain] # Skip verification if no domain configured

        attempts = 0
        url = build_health_check_url(service_name)

        loop do
          if traffic_reaching_container?(url, container)
            @logger.info "Traffic switch verification successful for #{service_name}"
            return true
          end

          attempts += 1
          if attempts >= max_attempts
            @logger.error "Traffic switch verification failed after #{max_attempts} attempts"
            return false
          end

          @logger.debug "Traffic switch verification attempt #{attempts}/#{max_attempts}..."
          sleep 2
        end
      end

      # Build health check URL for traffic verification
      #
      # @param service_name [String] Service name
      # @return [String] Health check URL
      def build_health_check_url(_service_name)
        protocol = @config[:ssl] ? "https" : "http"
        domain = @config[:domain] || @config[:host]
        path = @config[:health_check_path] || "/health"

        "#{protocol}://#{domain}#{path}"
      end

      # Check if traffic is reaching the specified container
      #
      # @param url [String] URL to check
      # @param container [Hash] Container information
      # @return [Boolean] True if traffic is reaching container
      def traffic_reaching_container?(url, container)
        require "net/http"
        require "uri"

        begin
          uri = URI(url)
          response = Net::HTTP.get_response(uri)

          # Check if response headers indicate traffic is coming from new container
          container_header = response["X-Container-ID"] || response["X-Container-Name"]
          if container_header
            container_header == container[:id] || container_header == container[:name]
          else
            # If no container headers, assume success if we get a successful response
            response.code.to_i.between?(200, 299)
          end
        rescue StandardError => e
          @logger.debug "Traffic verification request failed: #{e.message}"
          false
        end
      end

      # Generate upstream configuration block
      #
      # @param service_name [String] Service name
      # @param containers [Array<Hash>] Container information
      # @return [String] Upstream configuration
      def generate_upstream_config(service_name, containers)
        servers = containers.map do |container|
          host = container[:ip] || container[:host] || "localhost"
          port = extract_port_from_container(container)
          "    server #{host}:#{port};"
        end

        <<~CONFIG
          upstream #{service_name} {
          #{servers.join("\n")}
          }
        CONFIG
      end

      # Extract port from container configuration
      #
      # @param container [Hash] Container information
      # @return [Integer] Port number
      def extract_port_from_container(container)
        # Try to get port from container port mappings
        if container[:ports]&.any?
          # Format: ["80:3000"] -> extract the container port (3000)
          port_mapping = container[:ports].first
          port_mapping.split(":").last.to_i
        else
          # Default to app_port from config or 3000
          @config[:app_port] || 3000
        end
      end
    end
  end
end
