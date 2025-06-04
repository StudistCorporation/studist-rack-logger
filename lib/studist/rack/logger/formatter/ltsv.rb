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
                     .map { |key, value| "#{key}:#{escape_ltsv_value(serialize_value(value))}" }
                     .join("\t")
          end
        end
      end
    end
  end
end
