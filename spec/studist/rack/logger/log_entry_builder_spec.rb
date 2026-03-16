# frozen_string_literal: true

require 'spec_helper'
require 'socket'

RSpec.describe Studist::Rack::Logger::LogEntryBuilder do
  let(:default_options) { { app_id: 'test_app', log_version: '1.0.0' } }

  let(:env) do
    Rack::MockRequest.env_for(
      'http://example.org/test?param=value',
      method: 'GET',
      'REMOTE_ADDR' => '127.0.0.1',
      'HTTP_USER_AGENT' => 'TestAgent/1.0',
      'HTTP_REFERER' => 'https://example.com/previous',
      'HTTP_X_AMZN_TRACE_ID' => 'Root=1-test-trace-id',
      'HTTP_X_FORWARDED_FOR' => '203.0.113.1, 10.0.0.1',
      'CONTENT_LENGTH' => '42',
      'studist.request_id' => 'test-request-id-1234'
    )
  end

  let(:request) { Rack::Request.new(env) }
  let(:headers) { { 'Content-Length' => '100' } }
  let(:start_time) { Time.utc(2024, 1, 15, 10, 30, 45) }

  let(:context) do
    {
      env: env,
      request: request,
      request_path: request.path,
      status: 200,
      headers: headers,
      response_time_ms: 42,
      start_time: start_time,
      hostname: 'test-host',
      error: false,
    }
  end

  subject(:builder) { described_class.new(default_options, hostname: 'test-host') }

  describe '#build' do
    subject(:entry) { builder.build(context) }

    context 'basic fields' do
      it 'includes timestamp in ISO8601 format with milliseconds' do
        expect(entry[:timestamp]).to eq('2024-01-15T10:30:45.000Z')
      end

      it 'includes log_version' do
        expect(entry[:log_version]).to eq('1.0.0')
      end

      it 'includes app_id' do
        expect(entry[:app_id]).to eq('test_app')
      end

      it 'includes trace_id from X-Amzn-Trace-Id header' do
        expect(entry[:trace_id]).to eq('Root=1-test-trace-id')
      end

      it 'prefers X-Amzn-Trace-Id over X-Trace-Id' do
        env['HTTP_X_TRACE_ID'] = 'custom-trace'
        expect(entry[:trace_id]).to eq('Root=1-test-trace-id')
      end

      it 'falls back to X-Trace-Id when X-Amzn-Trace-Id is absent' do
        env.delete('HTTP_X_AMZN_TRACE_ID')
        env['HTTP_X_TRACE_ID'] = 'custom-trace-123'
        expect(entry[:trace_id]).to eq('custom-trace-123')
      end

      it 'includes request_id from env' do
        expect(entry[:request_id]).to eq('test-request-id-1234')
      end

      it 'includes server_name from cached hostname' do
        expect(entry[:server_name]).to eq('test-host')
      end
    end

    context 'request fields' do
      it 'includes request_method' do
        expect(entry[:request_method]).to eq('GET')
      end

      it 'includes full request_url with query string' do
        expect(entry[:request_url]).to eq('http://example.org/test?param=value')
      end

      it 'includes request_body_size from CONTENT_LENGTH' do
        expect(entry[:request_body_size]).to eq(42)
      end

      it 'includes query_string when present' do
        expect(entry[:query_string]).to eq('param=value')
      end

      it 'includes host' do
        expect(entry[:host]).to eq('example.org')
      end

      it 'includes user_agent' do
        expect(entry[:user_agent]).to eq('TestAgent/1.0')
      end

      it 'includes referer' do
        expect(entry[:referer]).to eq('https://example.com/previous')
      end

      it 'includes x_forwarded_for' do
        expect(entry[:x_forwarded_for]).to eq('203.0.113.1, 10.0.0.1')
      end

      it 'includes remote_addr' do
        expect(entry[:remote_addr]).to be_a(String)
        expect(entry[:remote_addr]).not_to be_empty
      end
    end

    context 'response fields' do
      it 'includes status_code as integer' do
        expect(entry[:status_code]).to eq(200)
      end

      it 'includes response_time_ms' do
        expect(entry[:response_time_ms]).to eq(42)
      end

      it 'includes response_body_size from Content-Length header' do
        expect(entry[:response_body_size]).to eq(100)
      end

      it 'accepts lowercase content-length header' do
        context[:headers] = { 'content-length' => '200' }
        expect(entry[:response_body_size]).to eq(200)
      end
    end

    context 'nil value handling' do
      let(:env) { Rack::MockRequest.env_for('/test', 'studist.request_id' => 'req-1') }
      let(:headers) { {} }

      it 'omits query_string when empty' do
        expect(entry).not_to have_key(:query_string)
      end

      it 'omits user_agent when not present' do
        expect(entry).not_to have_key(:user_agent)
      end

      it 'omits referer when not present' do
        expect(entry).not_to have_key(:referer)
      end

      it 'omits trace_id when not present' do
        expect(entry).not_to have_key(:trace_id)
      end

      it 'omits x_forwarded_for when not present' do
        expect(entry).not_to have_key(:x_forwarded_for)
      end

      it 'omits request_body_size when CONTENT_LENGTH is absent' do
        expect(entry).not_to have_key(:request_body_size)
      end

      it 'omits response_body_size when Content-Length header is absent' do
        expect(entry).not_to have_key(:response_body_size)
      end
    end

    context 'user fields with custom extractors' do
      let(:options) do
        default_options.merge(
          user_id_extractor: ->(_env, _req) { 'user123' },
          user_group_id_extractor: ->(_env, _req) { 'group456' },
          user_authority_extractor: ->(_env, _req) { 'admin' },
          normalized_uri_extractor: ->(_env, _req) { '/test/:id' }
        )
      end

      subject(:builder) { described_class.new(options, hostname: 'test-host') }

      it 'uses user_id_extractor' do
        expect(entry[:user_id]).to eq('user123')
      end

      it 'uses user_group_id_extractor' do
        expect(entry[:user_group_id]).to eq('group456')
      end

      it 'uses user_authority_extractor' do
        expect(entry[:user_authority]).to eq('admin')
      end

      it 'uses normalized_uri_extractor' do
        expect(entry[:normalized_uri]).to eq('/test/:id')
      end
    end

    context 'user fields without extractors' do
      it 'omits user_id' do
        expect(entry).not_to have_key(:user_id)
      end

      it 'omits user_group_id' do
        expect(entry).not_to have_key(:user_group_id)
      end

      it 'omits user_authority' do
        expect(entry).not_to have_key(:user_authority)
      end

      it 'omits normalized_uri' do
        expect(entry).not_to have_key(:normalized_uri)
      end
    end

    context 'server_name resolution' do
      context 'with hostname provided at initialization' do
        subject(:builder) { described_class.new(default_options, hostname: 'cached-host') }

        it 'uses the provided hostname' do
          expect(entry[:server_name]).to eq('cached-host')
        end
      end

      context 'without hostname provided' do
        subject(:builder) { described_class.new(default_options) }

        it 'falls back to Socket.gethostname' do
          expect(entry[:server_name]).to eq(Socket.gethostname)
        end

        it 'falls back to "unknown" when Socket.gethostname raises' do
          allow(Socket).to receive(:gethostname).and_raise(StandardError, 'unavailable')
          expect(entry[:server_name]).to eq('unknown')
        end
      end
    end

    context 'trusted proxy configuration' do
      let(:options) do
        default_options.merge(trusted_proxies: ['10.0.0.0/8'])
      end

      subject(:builder) { described_class.new(options, hostname: 'test-host') }

      it 'passes trusted_proxies to RemoteIp extractor' do
        expect(builder.instance_variable_get(:@remote_ip_extractor).trusted_proxies).not_to be_empty
      end
    end
  end
end
