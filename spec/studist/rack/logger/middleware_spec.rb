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

    context 'with trusted proxy configuration' do
      let(:options) do
        {
          logger: logger,
          app_id: 'test_app',
          log_version: '1.0.0',
          trusted_proxies: ['10.0.0.0/8', '172.16.0.0/12'],
        }
      end

      context 'with X-Forwarded-For from trusted proxy' do
        before do
          header 'X-Forwarded-For', '203.0.113.1, 198.51.100.1'
          env 'REMOTE_ADDR', '10.0.0.1' # trusted proxy
          get '/test'
        end

        it 'extracts real client IP from X-Forwarded-For' do
          log_entry = JSON.parse(log_output.string.strip)
          expect(log_entry['remote_addr']).to eq('198.51.100.1')
        end
      end

      context 'with X-Forwarded-For from untrusted proxy' do
        before do
          header 'X-Forwarded-For', '203.0.113.1'
          env 'REMOTE_ADDR', '198.51.100.1' # untrusted proxy
          get '/test'
        end

        it 'uses REMOTE_ADDR when proxy is not trusted' do
          log_entry = JSON.parse(log_output.string.strip)
          expect(log_entry['remote_addr']).to eq('198.51.100.1')
        end
      end

      context 'with IPv4-mapped IPv6 address' do
        before do
          header 'X-Forwarded-For', '::ffff:203.0.113.1'
          env 'REMOTE_ADDR', '10.0.0.1'
          get '/test'
        end

        it 'converts IPv4-mapped IPv6 to IPv4' do
          log_entry = JSON.parse(log_output.string.strip)
          expect(log_entry['remote_addr']).to eq('203.0.113.1')
        end
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

      it 'extracts remote_addr from X-Forwarded-For using trusted proxy logic' do
        log_entry = JSON.parse(log_output.string.strip)
        # With trusted proxy filtering, it finds the last untrusted IP in the chain
        expect(log_entry['remote_addr']).to eq('150.172.238.178')
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

    context 'when internal logging fails' do
      before { allow(logger).to receive(:info).and_raise(StandardError, 'logger failed') }

      it 'does not raise an exception' do
        expect { get '/test' }.not_to raise_error
      end

      it 'outputs a warning to stderr' do
        expect { get '/test' }.to output(/Studist::Rack::Logger failed to log/).to_stderr
      end
    end

    context 'when hostname cannot be determined' do
      let(:middleware) do
        allow(Socket).to receive(:gethostname).and_raise(StandardError, 'hostname unavailable')
        described_class.new(base_app, options)
      end

      before { get '/test' }

      it 'falls back to "unknown" as server_name' do
        log_entry = JSON.parse(log_output.string.strip)
        expect(log_entry['server_name']).to eq('unknown')
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

  describe 'complete log output verification' do
    context 'comprehensive test with all 22 fields' do
      let(:base_app) do
        proc { |_env|
          [201, { 'Content-Length' => '250', 'Content-Type' => 'application/json' }, ['{"data":"test"}']]
        }
      end
      let(:options) do
        {
          logger: logger,
          app_id: 'comprehensive_test_app',
          log_version: '2.0.0',
          user_id_extractor: ->(_env, _req) { 'user789' },
          user_group_id_extractor: ->(_env, _req) { 'group123' },
          user_authority_extractor: ->(_env, _req) { 'editor' },
          normalized_uri_extractor: ->(_env, _req) { '/api/test/:id' },
        }
      end

      before do
        header 'X-Amzn-Trace-Id', 'Root=1-test-trace-id'
        header 'X-Forwarded-For', '192.168.1.100, 10.0.0.1'
        header 'User-Agent', 'TestAgent/1.0'
        header 'Referer', 'https://test.example.com/previous'
        header 'Content-Length', '15'
        post '/api/test/123?filter=active&sort=name', 'test post data'
      end

      it 'outputs all 22 specification fields in JSON format' do
        log_entry = JSON.parse(log_output.string.strip)

        # Basic fields (6 items)
        expect(log_entry).to have_key('timestamp')
        expect(log_entry['timestamp']).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z/)
        expect(log_entry['log_version']).to eq('2.0.0')
        expect(log_entry['app_id']).to eq('comprehensive_test_app')
        expect(log_entry).to have_key('trace_id')
        expect(log_entry['trace_id']).to eq('Root=1-test-trace-id')
        expect(log_entry).to have_key('request_id')
        expect(log_entry['request_id']).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
        expect(log_entry).to have_key('server_name')
        expect(log_entry['server_name']).to be_a(String)

        # Request fields (7 items)
        expect(log_entry['status_code']).to eq(201)
        expect(log_entry['request_method']).to eq('POST')
        expect(log_entry['request_url']).to eq('http://example.org/api/test/123?filter=active&sort=name')
        expect(log_entry['request_body_size']).to eq(15)
        expect(log_entry['query_string']).to eq('filter=active&sort=name')
        expect(log_entry['host']).to eq('example.org')
        expect(log_entry['user_agent']).to eq('TestAgent/1.0')
        expect(log_entry['referer']).to eq('https://test.example.com/previous')
        # With trusted proxy filtering, both IPs are private so falls back to REMOTE_ADDR
        expect(log_entry['remote_addr']).to eq('127.0.0.1') # Default test REMOTE_ADDR
        expect(log_entry['x_forwarded_for']).to eq('192.168.1.100, 10.0.0.1')

        # Response fields (2 items)
        expect(log_entry).to have_key('response_time_ms')
        expect(log_entry['response_time_ms']).to be_a(Integer)
        expect(log_entry['response_body_size']).to eq(250)

        # User fields (3 items)
        expect(log_entry['normalized_uri']).to eq('/api/test/:id')
        expect(log_entry['user_id']).to eq('user789')
        expect(log_entry['user_group_id']).to eq('group123')
        expect(log_entry['user_authority']).to eq('editor')

        # Verify total count of fields matches specification
        expected_fields = %w[
          timestamp log_version app_id trace_id request_id server_name
          status_code request_method request_url request_body_size query_string host
          user_agent referer remote_addr x_forwarded_for response_time_ms response_body_size
          normalized_uri user_id user_group_id user_authority
        ]
        expect(log_entry.keys.sort).to eq(expected_fields.sort)
      end
    end

    context 'LTSV format with all 22 fields' do
      let(:options) do
        {
          logger: logger,
          app_id: 'ltsv_test_app',
          format: :ltsv,
          user_id_extractor: ->(_env, _req) { 'ltsv_user' },
          user_group_id_extractor: ->(_env, _req) { 'ltsv_group' },
          user_authority_extractor: ->(_env, _req) { 'ltsv_admin' },
          normalized_uri_extractor: ->(_env, _req) { '/ltsv/test' },
        }
      end

      before do
        header 'X-Amzn-Trace-Id', 'ltsv-trace'
        header 'Content-Length', '20'
        post '/test', 'ltsv test data'
      end

      it 'outputs all fields in LTSV format' do
        log_line = log_output.string.strip

        # Check for all 18 specification fields in LTSV format
        expect(log_line).to include('timestamp:')
        expect(log_line).to include('log_version:')
        expect(log_line).to include('app_id:ltsv_test_app')
        expect(log_line).to include('trace_id:ltsv-trace')
        expect(log_line).to include('request_id:')
        expect(log_line).to include('server_name:')
        expect(log_line).to include('status_code:200')
        expect(log_line).to include('request_method:POST')
        expect(log_line).to include('request_url:')
        expect(log_line).to include('request_body_size:20')
        expect(log_line).to include('host:example.org')
        expect(log_line).to include('response_time_ms:')
        expect(log_line).to include('normalized_uri:/ltsv/test')
        expect(log_line).to include('user_id:ltsv_user')
        expect(log_line).to include('user_group_id:ltsv_group')
        expect(log_line).to include('user_authority:ltsv_admin')

        # Verify LTSV format structure
        expect(log_line).to include("\t")
        expect(log_line).not_to include('{')
      end
    end

    context 'nil value handling verification' do
      let(:base_app) { proc { |_env| [200, {}, ['']] } }

      before { get '/test' }

      it 'handles nil values appropriately' do
        log_entry = JSON.parse(log_output.string.strip)

        # Fields that should never be nil (required by specification)
        expect(log_entry['timestamp']).not_to be_nil
        expect(log_entry['log_version']).not_to be_nil
        expect(log_entry['app_id']).not_to be_nil
        expect(log_entry['request_id']).not_to be_nil
        expect(log_entry['server_name']).not_to be_nil
        expect(log_entry['status_code']).not_to be_nil
        expect(log_entry['request_method']).not_to be_nil
        expect(log_entry['request_url']).not_to be_nil
        expect(log_entry['host']).not_to be_nil
        expect(log_entry['response_time_ms']).not_to be_nil

        # Fields that can be nil but are omitted due to .compact
        expect(log_entry).not_to have_key('query_string') # Empty query string
        expect(log_entry).not_to have_key('user_agent') # Not provided
        expect(log_entry).not_to have_key('referer') # Not provided
        expect(log_entry).not_to have_key('trace_id') # Not provided
        expect(log_entry).not_to have_key('x_forwarded_for') # Not provided
        expect(log_entry).not_to have_key('request_body_size') # No content-length
        expect(log_entry).not_to have_key('response_body_size') # No content-length
        expect(log_entry).not_to have_key('normalized_uri') # No extractor
        expect(log_entry).not_to have_key('user_id') # No extractor
        expect(log_entry).not_to have_key('user_group_id') # No extractor
        expect(log_entry).not_to have_key('user_authority') # No extractor

        # remote_addr should have a fallback value even without headers
        expect(log_entry).to have_key('remote_addr')
      end
    end
  end
end
