# frozen_string_literal: true

require 'json'
require 'securerandom'
require 'socket'
require 'rack'
require_relative 'log_entry_builder'

module Studist
  module Rack
    module Logger
      # Struct for standardizing response data
      Response = Struct.new(:status, :headers, keyword_init: true)

      # Core middleware that intercepts Rack requests and generates structured logs.
      #
      # This class handles the actual request processing, timing measurement, and log generation.
      # It extracts comprehensive request/response information and formats it according to
      # Studist's unified logging standard.
      #
      # @api private
      class Middleware
        # Initializes the middleware with a Rack application and configuration options.
        #
        # @param app [#call] The Rack application to wrap
        # @param options [Hash] Configuration options
        # @option options [String] :app_id ('unknown') Application identifier
        # @option options [Symbol] :format (:json) Log format - :json or :ltsv
        # @option options [Logger] :logger (Logger.new($stdout)) Logger instance
        # @option options [String] :log_version ('1.0.0') Log schema version
        # @option options [Proc] :user_id_extractor (nil) Extract user ID from request
        # @option options [Proc] :user_group_id_extractor (nil) Extract user group ID
        # @option options [Proc] :user_authority_extractor (nil) Extract user authority
        # @option options [Proc] :normalized_uri_extractor (nil) Extract normalized URI pattern
        # @option options [Float] :sampling_rate (1.0) Sampling rate for requests (0.0-1.0)
        # @option options [Float] :error_sampling_rate (1.0) Sampling rate for errors (0.0-1.0)
        # @param config [Configuration, nil] Optional configuration instance providing advanced features
        #   like DSL-based filtering, skip conditions, and global extractor registration.
        #   When provided, takes precedence over equivalent options hash parameters.
        def initialize(app, options = {}, config = nil)
          @app = app
          @options = default_options.merge(options)
          @config = config

          # Performance optimizations: cache hostname to avoid repeated system calls
          @hostname = fetch_hostname
          @sampling_rate = @options[:sampling_rate] || 1.0
          @error_sampling_rate = @options[:error_sampling_rate] || 1.0

          @logger = @options[:logger] || create_default_logger
          @formatter = create_formatter(@options[:format])
          @log_entry_builder = LogEntryBuilder.new(@options)
          @log_entry_builder.instance_variable_set(:@hostname, @hostname)
        end

        # Processes a Rack request and generates structured logs.
        #
        # This method wraps the application call, measures response time, and generates
        # a log entry with all standardized fields. It handles both successful responses
        # and exceptions.
        #
        # @param env [Hash] The Rack environment hash
        # @return [Array] Standard Rack response array [status, headers, body]
        def call(env)
          start_time = Time.now
          request = ::Rack::Request.new(env)

          # Generate request ID if not provided
          env['studist.request_id'] ||= SecureRandom.uuid

          process_request(env, request, start_time)
        rescue StandardError => e
          handle_error(env, request, start_time, e)
        end

        private

          def default_options
            {
              app_id: 'unknown',
              log_version: '1.0.0',
              format: :json,
              logger: nil,
              sampling_rate: 1.0,
              error_sampling_rate: 1.0,
              user_id_extractor: nil,
              user_group_id_extractor: nil,
              user_authority_extractor: nil,
              normalized_uri_extractor: nil,
            }
          end

          def create_default_logger
            require 'logger'
            ::Logger.new($stdout).tap do |logger|
              logger.formatter = proc { |_severity, _datetime, _progname, msg| "#{msg}\n" }
            end
          end

          def create_formatter(format_type)
            case format_type
            when :json
              Formatter::Json.new
            when :ltsv
              Formatter::Ltsv.new
            else
              raise ArgumentError, "Unsupported format: #{format_type}. Supported formats: :json, :ltsv"
            end
          end

          def process_request(env, request, start_time)
            status, headers, body = @app.call(env)

            response = Response.new(status: status, headers: headers)
            log_context = create_log_context(env, request, response, start_time)

            safe_log_request(log_context) if should_log?(log_context)

            [status, headers, body]
          end

          def handle_error(env, request, start_time, error)
            response = Response.new(status: 500, headers: {})
            log_context = create_log_context(env, request, response, start_time, is_error: true)
            log_context[:error] = {
              class: error.class.name,
              message: error.message,
              backtrace: filter_backtrace(error.backtrace),
            }

            safe_log_error(log_context) if should_log?(log_context)

            raise error
          end

          def create_log_context(env, request, response, start_time, is_error: false)
            {
              env: env,
              request: request,
              request_path: request.path,
              status: response.status,
              headers: response.headers,
              response_time_ms: calculate_response_time(start_time),
              start_time: start_time,
              hostname: @hostname,
              error: is_error,
            }
          end

          def calculate_response_time(start_time)
            ((Time.now - start_time) * 1000).round
          end

          def fetch_hostname
            Socket.gethostname
          rescue StandardError => e
            warn "Failed to get hostname: #{e.message}"
            'unknown'
          end

          def should_log?(log_context)
            # Use config-based filtering if available
            return @config.should_log?(log_context) if @config

            # Fallback to basic sampling
            sample_request?(log_context)
          end

          def sample_request?(log_context)
            rate = log_context[:error] ? @error_sampling_rate : @sampling_rate
            return true if rate >= 1.0

            rand < rate
          end

          def safe_log_request(log_context)
            log_entry = @log_entry_builder.build(log_context)
            @logger.info(@formatter.format(log_entry))
          rescue StandardError => e
            safe_log_failure('info', e)
          end

          def safe_log_error(log_context)
            log_entry = @log_entry_builder.build(log_context)
            @logger.error(@formatter.format(log_entry))
          rescue StandardError => e
            safe_log_failure('error', e)
          end

          def safe_log_failure(level, error)
            warn "Studist::Rack::Logger failed to log #{level}: #{error.message}"
          end

          def filter_backtrace(backtrace)
            return [] unless backtrace

            # Limit backtrace size and filter out gem paths for cleaner logs
            backtrace.take(10).reject { |line| line.include?('/gems/') }
          end
      end
    end
  end
end
