# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Studist::Rack::Logger do
  describe '.new' do
    it 'returns a Middleware instance' do
      app = proc { [200, {}, ['OK']] }
      middleware = described_class.new(app)
      expect(middleware).to be_a(Studist::Rack::Logger::Middleware)
    end

    it 'passes options to Middleware' do
      app = proc { [200, {}, ['OK']] }
      options = { app_id: 'test_app' }

      expect(Studist::Rack::Logger::Middleware).to receive(:new).with(app, options)
      described_class.new(app, options)
    end
  end
end
