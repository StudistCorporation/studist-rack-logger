# frozen_string_literal: true

module Studist
  module Rack
    module Logger
      # Formatters for converting log entries to different output formats.
      module Formatter
        # Abstract base class for log formatters.
        #
        # This class defines the interface that all formatters must implement
        # and provides common helper methods for value serialization and escaping.
        #
        # @abstract Subclass and override {#format} to implement a custom formatter.
        class Base
          # Formats a log entry hash into a string representation.
          #
          # @param log_entry [Hash] The log entry to format
          # @return [String] The formatted log entry
          # @abstract Subclass must implement this method
          def format(log_entry)
            raise NotImplementedError, 'Subclass must implement #format method'
          end

          private

            def serialize_value(value)
              return '' if value.nil?
              return value if value.is_a?(String)
              return value.to_s if value.is_a?(Integer) || value.is_a?(Float)
              return value.iso8601(3) if value.is_a?(Time)

              value.to_s
            end

            def escape_value(value, format_type)
              case format_type
              when :json
                value.to_json
              when :ltsv
                escape_ltsv_value(value)
              else
                value.to_s
              end
            end

            def escape_ltsv_value(value)
              return '' if value.nil?

              value.to_s
                   .gsub("\t", '\\t')
                   .gsub("\n", '\\n')
                   .gsub("\r", '\\r')
            end
        end
      end
    end
  end
end
