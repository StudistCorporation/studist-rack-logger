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

        end
      end
    end
  end
end
