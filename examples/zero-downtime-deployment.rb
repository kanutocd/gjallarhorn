#!/usr/bin/env ruby
# frozen_string_literal: true

# Example of zero-downtime deployment with Gjallarhorn
# This demonstrates the new deployment architecture with strategies and proxy management

require_relative "../lib/gjallarhorn"

# Example configuration for zero-downtime deployment
config_yml = <<~YAML
  production:
    provider: aws
    region: us-west-2
  #{"  "}
    # Proxy configuration for zero-downtime deployments
    proxy:
      type: nginx
      domain: myapp.example.com
      ssl: true
      health_check_path: /health
      conf_dir: /etc/nginx/conf.d
  #{"    "}
    services:
      - name: web
        ports: ["80:3000"]
        env:
          RAILS_ENV: production
          DATABASE_URL: postgresql://db.example.com/myapp_production
        healthcheck:
          type: http
          path: /health
          port: 3000
          expected_status: [200, 204]
          max_attempts: 30
          interval: 3
        drain_timeout: 30
        restart_policy: unless-stopped
  #{"    "}
      - name: worker
        env:
          RAILS_ENV: production
          DATABASE_URL: postgresql://db.example.com/myapp_production
        cmd: bundle exec sidekiq
        healthcheck:
          type: command
          command: pgrep -f sidekiq
        restart_policy: unless-stopped
YAML

# Write temporary config file
require "tempfile"
config_file = Tempfile.new(["deploy", ".yml"])
config_file.write(config_yml)
config_file.close

begin
  # Initialize deployer
  Gjallarhorn::Deployer.new(config_file.path)

  puts "🚀 Starting zero-downtime deployment..."
  puts "=" * 50

  # Deploy with zero-downtime strategy (default)
  puts "\n1. Deploying with zero-downtime strategy:"
  puts "   - Starts new containers alongside existing ones"
  puts "   - Waits for health checks to pass"
  puts "   - Switches nginx proxy traffic to new containers"
  puts "   - Gracefully stops old containers"
  puts ""

  # This would perform the actual deployment:
  # deployer.deploy('production', 'myapp:v2.1.0')

  # For demo purposes, show what strategies are available
  puts "✅ Available deployment strategies:"
  puts "   - zero_downtime: Full zero-downtime with proxy switching (default)"
  puts "   - basic: Stop old containers, start new ones (downtime expected)"
  puts "   - legacy: Use original adapter interface (for compatibility)"

  puts "\n📊 Zero-downtime deployment features:"
  puts "   ✅ Container orchestration with health checks"
  puts "   ✅ Nginx proxy management with traffic switching"
  puts "   ✅ Graceful container shutdown with drain timeout"
  puts "   ✅ Container versioning and cleanup"
  puts "   ✅ Rollback support (keeps old containers for quick rollback)"
  puts "   ✅ Multiple service support (web + worker)"
  puts "   ✅ HTTP and command-based health checks"

  puts "\n🔧 Proxy managers supported:"
  puts "   ✅ Nginx (fully implemented)"
  puts "   🚧 Traefik (placeholder - future release)"
  puts "   🚧 Kamal-proxy (placeholder - future release)"

  puts "\n💡 Usage examples:"
  puts "   deployer.deploy('production', 'myapp:v2.1.0')                    # Zero-downtime (default)"
  puts "   deployer.deploy('production', 'myapp:v2.1.0', strategy: 'basic') # Basic deployment"
  puts "   deployer.deploy_with_strategy('production', 'myapp:v2.1.0', 'zero_downtime')"
rescue Gjallarhorn::ConfigurationError => e
  puts "❌ Configuration error: #{e.message}"
rescue Gjallarhorn::DeploymentError => e
  puts "❌ Deployment error: #{e.message}"
ensure
  config_file&.unlink
end
