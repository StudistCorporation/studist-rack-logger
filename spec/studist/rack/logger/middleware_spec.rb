# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'logger'

RSpec.describe Studist::Rack::Logger::Middleware do
  let(:base_app) { proc { |_env| [200, { 'Content-Type' => 'text/plain' }, ['Hello World']] } }
  let(:log_output) { StringIO.new }
  let(:logger) { Logger.new(log_output).tap { |l| l.formatter = proc { |_s, _d, _p, msg| "#{msg}\n" } } }
  let(:options) { { logger: logger, app_id: 'test_app', log_version: '1.0.0' } }
  let(:middleware) { described_class.new(base_app, options) }

  let(:app) { middleware }

  describe '#call' do
    context 'with successful request' do
      before { get '/test?param=value' }

      it 'logs request information in JSON format' do
        log_entry = JSON.parse(log_output.string.strip)

        expect(log_entry['timestamp']).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z/)
        expect(log_entry['log_version']).to eq('1.0.0')
        expect(log_entry['app_id']).to eq('test_app')
        expect(log_entry['status_code']).to eq(200)
        expect(log_entry['request_method']).to eq('GET')
        expect(log_entry['request_url']).to eq('http://example.org/test?param=value')
        expect(log_entry['query_string']).to eq('param=value')
        expect(log_entry['host']).to eq('example.org')
        expect(log_entry['response_time_ms']).to be_a(Integer)
        expect(log_entry['response_time_ms']).to be >= 0
      end

      it 'includes server_name' do
        log_entry = JSON.parse(log_output.string.strip)
        expect(log_entry['server_name']).to be_a(String)
        expect(log_entry['server_name']).not_to be_empty
      end

      it 'generates request_id' do
        log_entry = JSON.parse(log_output.string.strip)
        expect(log_entry['request_id']).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
      end
    end

    context 'with trace_id header' do
      before do
        header 'X-Amzn-Trace-Id', 'Root=1-5e1b4151-5ac6c58142935a3c7c42d1c7'
        get '/test'
      end

      it 'includes trace_id in log' do
        log_entry = JSON.parse(log_output.string.strip)
        expect(log_entry['trace_id']).to eq('Root=1-5e1b4151-5ac6c58142935a3c7c42d1c7')
      end
    end

    context 'with X-Forwarded-For header' do
      before do
        header 'X-Forwarded-For', '203.0.113.195, 70.41.3.18, 150.172.238.178'
        get '/test'
      end

      it 'extracts remote_addr from X-Forwarded-For' do
        log_entry = JSON.parse(log_output.string.strip)
        expect(log_entry['remote_addr']).to eq('203.0.113.195')
        expect(log_entry['x_forwarded_for']).to eq('203.0.113.195, 70.41.3.18, 150.172.238.178')
      end
    end

    context 'with user agent and referer' do
      before do
        header 'User-Agent', 'Mozilla/5.0 (Test Browser)'
        header 'Referer', 'https://example.com/previous'
        get '/test'
      end

      it 'includes user_agent and referer' do
        log_entry = JSON.parse(log_output.string.strip)
        expect(log_entry['user_agent']).to eq('Mozilla/5.0 (Test Browser)')
        expect(log_entry['referer']).to eq('https://example.com/previous')
      end
    end

    context 'with POST request and body' do
      before do
        header 'Content-Length', '13'
        post '/test', 'Hello, World!'
      end

      it 'includes request_body_size' do
        log_entry = JSON.parse(log_output.string.strip)
        expect(log_entry['request_body_size']).to eq(13)
      end
    end

    context 'with custom extractors' do
      let(:options) do
        {
          logger: logger,
          app_id: 'test_app',
          user_id_extractor: ->(_env, _req) { 'user123' },
          user_group_id_extractor: ->(_env, _req) { 'group456' },
          user_authority_extractor: ->(_env, _req) { 'admin' },
          normalized_uri_extractor: ->(_env, _req) { '/test/:id' },
        }
      end

      before { get '/test' }

      it 'uses custom extractors' do
        log_entry = JSON.parse(log_output.string.strip)
        expect(log_entry['user_id']).to eq('user123')
        expect(log_entry['user_group_id']).to eq('group456')
        expect(log_entry['user_authority']).to eq('admin')
        expect(log_entry['normalized_uri']).to eq('/test/:id')
      end
    end

    context 'when app raises an exception' do
      let(:base_app) { proc { |_env| raise StandardError, 'Something went wrong' } }

      it 'logs error with 500 status and re-raises exception' do
        expect { get '/test' }.to raise_error(StandardError, 'Something went wrong')

        log_entry = JSON.parse(log_output.string.strip)
        expect(log_entry['status_code']).to eq(500)
        expect(log_entry['response_time_ms']).to be_a(Integer)
      end
    end

    context 'with different response status codes' do
      let(:base_app) { proc { |_env| [404, { 'Content-Type' => 'text/plain' }, ['Not Found']] } }

      before { get '/test' }

      it 'logs the actual status code' do
        log_entry = JSON.parse(log_output.string.strip)
        expect(log_entry['status_code']).to eq(404)
      end
    end

    context 'without query string' do
      before { get '/test' }

      it 'omits query_string when empty' do
        log_entry = JSON.parse(log_output.string.strip)
        expect(log_entry).not_to have_key('query_string')
      end
    end

    context 'with response Content-Length header' do
      let(:base_app) { proc { |_env| [200, { 'Content-Length' => '100' }, ['Response']] } }

      before { get '/test' }

      it 'includes response_body_size' do
        log_entry = JSON.parse(log_output.string.strip)
        expect(log_entry['response_body_size']).to eq(100)
      end
    end
  end

  describe 'default options' do
    let(:default_middleware) { described_class.new(base_app) }

    let(:app) { default_middleware }

    before { get '/test' }

    it 'uses default values' do
      # Since we can't easily test the default logger output, we'll just verify the middleware doesn't crash
      expect(last_response.status).to eq(200)
    end
  end

  describe 'format option' do
    context 'with LTSV format' do
      let(:options) { { logger: logger, app_id: 'test_app', format: :ltsv } }

      before { get '/test?param=value' }

      it 'outputs in LTSV format' do
        log_line = log_output.string.strip

        expect(log_line).to include('timestamp:')
        expect(log_line).to include('app_id:test_app')
        expect(log_line).to include('status_code:200')
        expect(log_line).to include('request_method:GET')
        expect(log_line).to include("\t") # Tab separated
        expect(log_line).not_to include('{') # Not JSON
      end
    end

    context 'with invalid format' do
      it 'raises ArgumentError' do
        expect do
          described_class.new(base_app, format: :invalid)
        end.to raise_error(ArgumentError, 'Unsupported format: invalid. Supported formats: :json, :ltsv')
      end
    end
  end
end
