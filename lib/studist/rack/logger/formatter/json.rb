# frozen_string_literal: true

require 'json'

module Studist
  module Rack
    module Logger
      module Formatter
        class Json < Base
          def format(log_entry)
            log_entry.to_json
          end
        end
      end
    end
  end
end
