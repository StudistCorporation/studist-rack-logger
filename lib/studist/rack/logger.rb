# frozen_string_literal: true

require_relative 'logger/version'
require_relative 'logger/configuration'
require_relative 'logger/middleware'
require_relative 'logger/formatter'
require_relative 'logger/formatter/json'
require_relative 'logger/formatter/ltsv'

# Studist namespace for company-wide Ruby libraries and tools.
module Studist
  # Rack-related middleware and utilities for web applications.
  module Rack
    # Unified structured logging middleware for Rack applications following Studist's common log format.
    #
    # This middleware provides structured JSON or LTSV logging with 18 standardized fields including
    # timestamp, trace_id, user information, and response metrics.
    #
    # @example Basic usage
    #   # In a Rack application
    #   use Studist::Rack::Logger, app_id: 'my-service'
    #
    # @example Rails configuration
    #   # In config/application.rb
    #   config.middleware.use Studist::Rack::Logger,
    #     app_id: 'my-rails-app',
    #     format: :json,
    #     logger: Rails.logger
    #
    # @example Custom extractors
    #   use Studist::Rack::Logger,
    #     app_id: 'my-service',
    #     user_id_extractor: ->(env, req) { env['user.id'] },
    #     normalized_uri_extractor: ->(env, req) { normalize_path(req.path) }
    #
    # @example Configuration DSL
    #   Studist::Rack::Logger.configure do |config|
    #     config.app_id = 'my-service'
    #     config.format = :json
    #     config.sampling_rate = 0.1          # Log 10% of requests
    #     config.error_sampling_rate = 1.0     # Always log errors
    #     config.skip_paths = %w[/health /metrics]
    #     config.skip_if { |ctx| ctx[:status] == 200 && ctx[:request_path].start_with?('/assets') }
    #     config.filter { |ctx| ctx[:error] || ctx[:response_time_ms] > 1000 }
    #     config.extractor(:user_id) { |env, req| env['user.id'] }
    #   end
    #
    #   use Studist::Rack::Logger
    module Logger
      # Base error class for the Studist Rack Logger gem.
      #
      # All custom exceptions raised by this gem inherit from this class.
      class Error < StandardError; end

      class << self
        # Global configuration instance
        attr_reader :config

        # Configure the logger with a block
        #
        # @yield [config] The configuration instance
        # @yieldparam config [Configuration] The configuration object
        # @example
        #   Studist::Rack::Logger.configure do |config|
        #     config.app_id = 'my-service'
        #     config.format = :json
        #   end
        def configure
          @config ||= Configuration.new
          yield(@config) if block_given?
          @config
        end

        # Reset configuration to defaults
        def reset_config!
          @config = Configuration.new
        end

        # Creates a new instance of the logging middleware.
        #
        # @param app [#call] The Rack application
        # @param options [Hash] Configuration options (optional if using global config)
        # @option options [String] :app_id ('unknown') Application identifier
        # @option options [Symbol] :format (:json) Log format - :json or :ltsv
        # @option options [Logger] :logger (Logger.new($stdout)) Logger instance
        # @option options [String] :log_version ('1.0.0') Log schema version
        # @option options [Float] :sampling_rate (1.0) Sampling rate for requests (0.0-1.0)
        # @option options [Float] :error_sampling_rate (1.0) Sampling rate for errors (0.0-1.0)
        # @option options [Proc] :user_id_extractor (nil) Extract user ID from request
        # @option options [Proc] :user_group_id_extractor (nil) Extract user group ID
        # @option options [Proc] :user_authority_extractor (nil) Extract user authority
        # @option options [Proc] :normalized_uri_extractor (nil) Extract normalized URI pattern
        # @return [Middleware] The middleware instance
        #
        # @see Middleware#initialize
        def new(app, options = {})
          if options.empty? && @config
            # Use global configuration
            Middleware.new(app, @config.to_middleware_options, @config)
          else
            # Use provided options (backward compatibility)
            Middleware.new(app, options)
          end
        end
      end
    end
  end
end
