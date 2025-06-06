# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Configuration Integration' do
  include Rack::Test::Methods

  let(:base_app) { proc { |_env| [200, { 'Content-Type' => 'text/plain' }, ['Hello World']] } }
  let(:log_output) { StringIO.new }
  let(:logger) { Logger.new(log_output).tap { |l| l.formatter = proc { |_s, _d, _p, msg| "#{msg}\n" } } }

  after do
    # Reset global configuration after each test
    Studist::Rack::Logger.reset_config!
  end

  describe 'global configuration' do
    let(:app) do
      Studist::Rack::Logger.configure do |config|
        config.app_id = 'test-app'
        config.logger = logger
        config.format = :json
        config.sampling_rate = 1.0
        config.extractor(:user_id) { |env, _req| env['HTTP_X_USER_ID'] }
      end

      Studist::Rack::Logger.new(base_app)
    end

    it 'uses global configuration' do
      header 'X-User-ID', 'user123'
      get '/test'

      log_entry = JSON.parse(log_output.string.strip)
      expect(log_entry['app_id']).to eq('test-app')
      expect(log_entry['user_id']).to eq('user123')
      expect(log_entry['status_code']).to eq(200)
    end
  end

  describe 'configuration with filtering' do
    let(:app) do
      Studist::Rack::Logger.configure do |config|
        config.app_id = 'test-app'
        config.logger = logger
        config.skip_paths = ['/health']
        config.skip_if { |context| context[:status] == 200 && context[:request_path] == '/skip-me' }
      end

      Studist::Rack::Logger.new(base_app)
    end

    it 'skips logging for configured paths' do
      get '/health'

      expect(log_output.string.strip).to be_empty
    end

    it 'skips logging based on conditions' do
      get '/skip-me'

      expect(log_output.string.strip).to be_empty
    end

    it 'logs normally for other paths' do
      get '/test'

      log_entry = JSON.parse(log_output.string.strip)
      expect(log_entry['app_id']).to eq('test-app')
      expect(log_entry['status_code']).to eq(200)
    end
  end

  describe 'configuration with sampling' do
    let(:app) do
      Studist::Rack::Logger.configure do |config|
        config.app_id = 'test-app'
        config.logger = logger
        config.sampling_rate = 0.0 # Never log normal requests
        config.error_sampling_rate = 1.0 # Always log errors
      end

      Studist::Rack::Logger.new(base_app)
    end

    it 'respects sampling rates' do
      get '/test'

      expect(log_output.string.strip).to be_empty
    end

    context 'with errors' do
      let(:base_app) { proc { |_env| raise StandardError, 'Test error' } }

      it 'logs errors despite low sampling rate' do
        expect { get '/test' }.to raise_error(StandardError, 'Test error')

        log_entry = JSON.parse(log_output.string.strip)
        expect(log_entry['status_code']).to eq(500)
      end
    end
  end

  describe 'backward compatibility' do
    let(:app) do
      # Old style configuration should still work
      Studist::Rack::Logger.new(base_app, {
                                  app_id: 'legacy-app',
                                  logger: logger,
                                  format: :json,
                                })
    end

    it 'works with hash-based configuration' do
      get '/test'

      log_entry = JSON.parse(log_output.string.strip)
      expect(log_entry['app_id']).to eq('legacy-app')
      expect(log_entry['status_code']).to eq(200)
    end
  end

  describe 'configuration validation' do
    it 'validates format on configure' do
      expect do
        Studist::Rack::Logger.configure do |config|
          config.format = :invalid
        end

        Studist::Rack::Logger.new(base_app)
      end.to raise_error(ArgumentError, /Unsupported format: invalid/)
    end

    it 'validates sampling rates' do
      expect do
        Studist::Rack::Logger.configure do |config|
          config.sampling_rate = 1.5
        end

        Studist::Rack::Logger.new(base_app)
      end.to raise_error(ArgumentError, /sampling_rate must be a number between 0.0 and 1.0/)
    end
  end
end
