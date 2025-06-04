# frozen_string_literal: true

require 'json'
require 'securerandom'
require_relative 'log_entry_builder'

module Studist
  module Rack
    module Logger
      class Middleware
        def initialize(app, options = {})
          @app = app
          @options = default_options.merge(options)
          @logger = @options[:logger] || create_default_logger
          @formatter = create_formatter(@options[:format])
          @log_entry_builder = LogEntryBuilder.new(@options)
        end

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
            log_context = create_log_context(env, request, status, headers, start_time)
            log_entry = @log_entry_builder.build(log_context)
            @logger.info(@formatter.format(log_entry))
            [status, headers, body]
          end

          def handle_error(env, request, start_time, error)
            log_context = create_log_context(env, request, 500, {}, start_time)
            log_entry = @log_entry_builder.build(log_context)
            @logger.error(@formatter.format(log_entry))
            raise error
          end

          def create_log_context(env, request, status, headers, start_time)
            {
              env: env,
              request: request,
              status: status,
              headers: headers,
              response_time_ms: calculate_response_time(start_time),
              start_time: start_time,
            }
          end

          def calculate_response_time(start_time)
            ((Time.now - start_time) * 1000).round
          end
      end
    end
  end
end
