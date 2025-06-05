# frozen_string_literal: true

require 'socket'

module Studist
  module Rack
    module Logger
      # Builds structured log entries from request context.
      #
      # This class extracts and organizes request/response information into
      # a standardized hash structure with 18 fields following Studist's
      # common log format specification.
      #
      # @api private
      class LogEntryBuilder
        # Initializes the builder with configuration options.
        #
        # @param options [Hash] Configuration options including extractors
        def initialize(options)
          @options = options
        end

        # Builds a complete log entry from request context.
        #
        # Combines basic metadata, request information, response details,
        # and user context into a unified log entry structure.
        #
        # @param context [Hash] Request processing context
        # @option context [Hash] :env Rack environment
        # @option context [Rack::Request] :request Request object
        # @option context [Integer] :status HTTP status code
        # @option context [Hash] :headers Response headers
        # @option context [Integer] :response_time_ms Response time in milliseconds
        # @option context [Time] :start_time Request start time
        # @option context [String] :hostname Cached hostname
        # @option context [Boolean] :error Whether this is an error response
        # @option context [Hash] :error Error details (class, message, backtrace) when error: true
        # @return [Hash] Complete log entry with standardized fields
        def build(context)
          basic_fields(context).merge(
            request_fields(context),
            response_fields(context),
            user_fields(context)
          ).compact
        end

        private

          def basic_fields(context)
            {
              timestamp: context[:start_time].utc.iso8601(3),
              log_version: @options[:log_version],
              app_id: @options[:app_id],
              trace_id: extract_trace_id(context[:env]),
              request_id: context[:env]['studist.request_id'],
              server_name: extract_server_name(context[:env]),
            }
          end

          def request_fields(context)
            env = context[:env]
            request = context[:request]

            {
              request_method: request.request_method,
              request_url: build_request_url(request),
              request_body_size: extract_request_body_size(env),
              query_string: request.query_string.empty? ? nil : request.query_string,
              host: request.host,
              user_agent: env['HTTP_USER_AGENT'],
              referer: env['HTTP_REFERER'],
              remote_addr: extract_remote_addr(env),
              x_forwarded_for: env['HTTP_X_FORWARDED_FOR'],
            }
          end

          def response_fields(context)
            {
              status_code: context[:status].to_i,
              response_time_ms: context[:response_time_ms],
              response_body_size: extract_response_body_size(context[:headers]),
            }
          end

          def user_fields(context)
            env = context[:env]
            request = context[:request]

            {
              normalized_uri: extract_normalized_uri(env, request),
              user_id: extract_user_id(env, request),
              user_group_id: extract_user_group_id(env, request),
              user_authority: extract_user_authority(env, request),
            }
          end

          def extract_trace_id(env)
            env['HTTP_X_AMZN_TRACE_ID'] || env['HTTP_X_TRACE_ID']
          end

          def extract_server_name(_env)
            # Use cached hostname from middleware if available
            return @hostname if defined?(@hostname) && @hostname

            # Fallback to system hostname
            Socket.gethostname
          rescue StandardError
            'unknown'
          end

          def build_request_url(request)
            "#{request.scheme}://#{request.host_with_port}#{request.fullpath}"
          end

          def extract_request_body_size(env)
            content_length = env['CONTENT_LENGTH']
            content_length&.to_i
          end

          def extract_remote_addr(env)
            forwarded_for = env['HTTP_X_FORWARDED_FOR']
            if forwarded_for
              forwarded_for.split(',').first.strip
            else
              env['HTTP_X_REAL_IP'] || env['REMOTE_ADDR']
            end
          end

          def extract_response_body_size(headers)
            content_length = headers['Content-Length'] || headers['content-length']
            content_length&.to_i
          end

          def extract_normalized_uri(env, request)
            return unless @options[:normalized_uri_extractor]
            @options[:normalized_uri_extractor].call(env, request)
          end

          def extract_user_id(env, request)
            return unless @options[:user_id_extractor]
            @options[:user_id_extractor].call(env, request)
          end

          def extract_user_group_id(env, request)
            return unless @options[:user_group_id_extractor]
            @options[:user_group_id_extractor].call(env, request)
          end

          def extract_user_authority(env, request)
            return unless @options[:user_authority_extractor]
            @options[:user_authority_extractor].call(env, request)
          end
      end
    end
  end
end
