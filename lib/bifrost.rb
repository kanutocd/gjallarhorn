# frozen_string_literal: true

require_relative "bifrost/version"

module Bifrost
  class Error < StandardError; end
end

require_relative "bifrost/configuration"
require_relative "bifrost/deployer"
require_relative "bifrost/cli"
