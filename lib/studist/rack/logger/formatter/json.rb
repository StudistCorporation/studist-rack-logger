# frozen_string_literal: true

require 'json'

module Studist
  module Rack
    module Logger
      module Formatter
        # JSON formatter for structured log output.
        #
        # Converts log entries to single-line JSON format suitable for
        # structured log processing and analysis.
        #
        # @example Output format
        #   {"timestamp":"2024-01-15T10:30:45.123Z","app_id":"my-service","status_code":200}
        class Json < Base
          # Formats a log entry as JSON.
          #
          # @param log_entry [Hash] The log entry to format
          # @return [String] Single-line JSON representation
          def format(log_entry)
            log_entry.to_json
          end
        end
      end
    end
  end
end
