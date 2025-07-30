# frozen_string_literal: true

require_relative "gjallarhorn/version"

# Gjallarhorn - Multi-cloud deployment guardian
#
# Gjallarhorn provides a unified interface for deploying containerized applications
# across different cloud providers using their native APIs. Named after Heimdall's horn
# in Norse mythology that sounds across all realms, Gjallarhorn enables secure,
# API-first deployments beyond traditional SSH-based tools.
#
# @example Basic usage
#   deployer = Gjallarhorn::Deployer.new('deploy.yml')
#   deployer.deploy('production', 'myapp:v1.0.0')
#   deployer.status('production')
#
# @author Ken C. Demanawa
# @since 0.1.0
module Gjallarhorn
  # Base error class for all Gjallarhorn-specific errors
  class Error < StandardError; end
end

require_relative "gjallarhorn/configuration"
require_relative "gjallarhorn/deployer"
require_relative "gjallarhorn/cli"
require_relative "gjallarhorn/history"
