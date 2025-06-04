# frozen_string_literal: true

require_relative 'logger/version'
require_relative 'logger/middleware'
require_relative 'logger/formatter'
require_relative 'logger/formatter/json'
require_relative 'logger/formatter/ltsv'

module Studist
  module Rack
    module Logger
      class Error < StandardError; end

      def self.new(app, options = {})
        Middleware.new(app, options)
      end
    end
  end
end
