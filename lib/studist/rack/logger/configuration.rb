# frozen_string_literal: true

module Studist
  module Rack
    module Logger
      # Configuration class for Studist::Rack::Logger
      #
      # Provides a DSL for configuring the logger middleware with validation
      # and support for global extractor registration.
      #
      # @example Basic configuration
      #   Studist::Rack::Logger.configure do |config|
      #     config.app_id = 'my-service'
      #     config.format = :json
      #     config.sampling_rate = 0.1
      #   end
      #
      # @example With extractors and filters
      #   Studist::Rack::Logger.configure do |config|
      #     config.extractor(:user_id) { |env, req| env['user.id'] }
      #     config.skip_paths = %w[/health /metrics]
      #     config.skip_if { |context| context[:status] == 200 }
      #   end
      class Configuration
        attr_accessor :app_id, :format, :logger, :log_version, :sampling_rate, :error_sampling_rate
        attr_reader :extractors, :filters, :skip_paths, :skip_conditions

        # Valid log formats
        VALID_FORMATS = %i[json ltsv].freeze

        def initialize
          @app_id = 'unknown'
          @format = :json
          @logger = nil
          @log_version = '1.0.0'
          @sampling_rate = 1.0
          @error_sampling_rate = 1.0
          @extractors = {}
          @filters = []
          @skip_paths = []
          @skip_conditions = []
        end

        # Register a custom extractor
        #
        # @param name [Symbol] The name of the field to extract
        # @param block [Proc] The extractor proc that takes (env, request) and returns a value
        # @example
        #   config.extractor(:user_id) { |env, req| env['user.id'] }
        def extractor(name, &block)
          raise ArgumentError, 'Block is required for extractor' unless block_given?

          @extractors[name.to_sym] = block
        end

        # Add a filter condition
        #
        # Filters are applied after skip conditions and sampling. All filters must return true for logging to occur.
        #
        # @param block [Proc] A proc that takes a log context and returns true to log, false to skip
        # @example Only log errors and slow requests
        #   config.filter { |context| context[:error] || context[:response_time_ms] > 1000 }
        def filter(&block)
          raise ArgumentError, 'Block is required for filter' unless block_given?

          @filters << block
        end

        # Skip logging for specific paths
        #
        # @param paths [Array<String>] Array of path patterns to skip
        def skip_paths=(paths)
          @skip_paths = Array(paths)
        end

        # Add a condition to skip logging
        #
        # @param block [Proc] A proc that takes a log context and returns true to skip logging
        def skip_if(&block)
          raise ArgumentError, 'Block is required for skip_if' unless block_given?

          @skip_conditions << block
        end

        # Validate the configuration
        #
        # @raise [ArgumentError] if configuration is invalid
        def validate!
          validate_format!
          validate_sampling_rates!
          validate_extractors!
        end

        # Convert configuration to options hash for middleware
        #
        # @return [Hash] Options hash for middleware initialization
        def to_middleware_options
          validate!

          {
            app_id: @app_id,
            format: @format,
            logger: @logger,
            log_version: @log_version,
            sampling_rate: @sampling_rate,
            error_sampling_rate: @error_sampling_rate,
            **extractor_options,
          }
        end

        # Check if a request should be logged based on filters and conditions
        #
        # Evaluation order: skip_paths → skip_conditions → sampling → filters
        #
        # @param context [Hash] The log context with keys like :request_path, :status, :error, :response_time_ms
        # @return [Boolean] true if should log, false otherwise
        def should_log?(context)
          return false if skip_path?(context[:request_path])
          return false if skip_conditions_match?(context)
          return false unless sample_request?(context)

          filters_pass?(context)
        end

        private

          def validate_format!
            return if VALID_FORMATS.include?(@format)

            raise ArgumentError, "Unsupported format: #{@format}. Supported formats: #{VALID_FORMATS.join(', ')}"
          end

          def validate_sampling_rates!
            validate_sampling_rate!(@sampling_rate, 'sampling_rate')
            validate_sampling_rate!(@error_sampling_rate, 'error_sampling_rate')
          end

          def validate_sampling_rate!(rate, name)
            return if rate.is_a?(Numeric) && rate >= 0.0 && rate <= 1.0

            raise ArgumentError, "#{name} must be a number between 0.0 and 1.0, got: #{rate}"
          end

          def validate_extractors!
            @extractors.each do |name, extractor|
              next if extractor.respond_to?(:call)

              raise ArgumentError, "Extractor #{name} must respond to call, got: #{extractor.class}"
            end
          end

          def extractor_options
            options = {}
            @extractors.each do |name, extractor|
              option_key = :"#{name}_extractor"
              options[option_key] = extractor
            end
            options
          end

          def skip_path?(path)
            @skip_paths.any? { |skip_path| path&.start_with?(skip_path) }
          end

          def skip_conditions_match?(context)
            @skip_conditions.any? { |condition| condition.call(context) }
          end

          def sample_request?(context)
            rate = context[:error] ? @error_sampling_rate : @sampling_rate
            return true if rate >= 1.0

            rand < rate
          end

          def filters_pass?(context)
            return true if @filters.empty?

            @filters.all? { |filter| filter.call(context) }
          end
      end
    end
  end
end
