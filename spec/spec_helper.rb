# frozen_string_literal: true

require 'bundler/setup'
require 'studist/rack/logger'
require 'rack/test'
require 'json'

RSpec.configure do |config|
  config.example_status_persistence_file_path = '.rspec_status'
  config.disable_monkey_patching!
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.include Rack::Test::Methods
end
