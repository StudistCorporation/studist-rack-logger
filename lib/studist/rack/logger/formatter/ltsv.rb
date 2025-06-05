# frozen_string_literal: true

module Studist
  module Rack
    module Logger
      module Formatter
        # LTSV (Labeled Tab-Separated Values) formatter for structured log output.
        #
        # Converts log entries to LTSV format, which is human-readable while
        # still being machine-parseable. Each field is labeled and separated by tabs.
        #
        # @example Output format
        #   timestamp:2024-01-15T10:30:45.123Z\tapp_id:my-service\tstatus_code:200
        #
        # @see https://ltsv.org/ LTSV specification
        class Ltsv < Base
          # Formats a log entry as LTSV.
          #
          # @param log_entry [Hash] The log entry to format
          # @return [String] Tab-separated labeled values with proper escaping
          def format(log_entry)
            log_entry.compact
                     .map { |key, value| "#{key}:#{escape_value(serialize_value(value))}" }
                     .join("\t")
          end

          private

          def serialize_value(value)
            return '' if value.nil?
            return value if value.is_a?(String)
            return value.to_s if value.is_a?(Integer) || value.is_a?(Float)
            return value.iso8601(3) if value.is_a?(Time)

            value.to_s
          end

          def escape_value(value)
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
