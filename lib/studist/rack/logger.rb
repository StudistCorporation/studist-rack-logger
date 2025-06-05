# frozen_string_literal: true

require_relative 'logger/version'
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
    module Logger
      # Base error class for the Studist Rack Logger gem.
      #
      # All custom exceptions raised by this gem inherit from this class.
      class Error < StandardError; end

      # Creates a new instance of the logging middleware.
      #
      # @param app [#call] The Rack application
      # @param options [Hash] Configuration options
      # @option options [String] :app_id ('unknown') Application identifier
      # @option options [Symbol] :format (:json) Log format - :json or :ltsv
      # @option options [Logger] :logger (Logger.new($stdout)) Logger instance
      # @option options [String] :log_version ('1.0.0') Log schema version
      # @option options [Proc] :user_id_extractor (nil) Extract user ID from request
      # @option options [Proc] :user_group_id_extractor (nil) Extract user group ID
      # @option options [Proc] :user_authority_extractor (nil) Extract user authority
      # @option options [Proc] :normalized_uri_extractor (nil) Extract normalized URI pattern
      # @return [Middleware] The middleware instance
      #
      # @see Middleware#initialize
      def self.new(app, options = {})
        Middleware.new(app, options)
      end
    end
  end
end
