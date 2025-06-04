# frozen_string_literal: true

module Studist
  module Rack
    module Logger
      module Formatter
        class Ltsv < Base
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
