# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Studist::Rack::Logger::Formatter do
  describe Studist::Rack::Logger::Formatter::Json do
    let(:formatter) { described_class.new }
    let(:log_entry) do
      {
        timestamp: '2023-01-01T10:00:00.000Z',
        log_version: '1.0.0',
        app_id: 'test_app',
        status_code: 200,
        request_method: 'GET',
        request_url: 'https://example.com/test?param=value',
        query_string: 'param=value',
        response_time_ms: 45,
      }
    end

    describe '#format' do
      it 'formats log entry as JSON' do
        result = formatter.format(log_entry)
        parsed = JSON.parse(result)

        expect(parsed['timestamp']).to eq('2023-01-01T10:00:00.000Z')
        expect(parsed['app_id']).to eq('test_app')
        expect(parsed['status_code']).to eq(200)
        expect(parsed['response_time_ms']).to eq(45)
      end

      it 'handles nil values by including them in JSON' do
        log_entry[:user_id] = nil
        result = formatter.format(log_entry)
        parsed = JSON.parse(result)

        expect(parsed).to have_key('user_id')
        expect(parsed['user_id']).to be_nil
      end
    end
  end

  describe Studist::Rack::Logger::Formatter::Ltsv do
    let(:formatter) { described_class.new }
    let(:log_entry) do
      {
        timestamp: '2023-01-01T10:00:00.000Z',
        log_version: '1.0.0',
        app_id: 'test_app',
        status_code: 200,
        request_method: 'GET',
        request_url: 'https://example.com/test?param=value',
        query_string: 'param=value',
        response_time_ms: 45,
      }
    end

    describe '#format' do
      it 'formats log entry as LTSV' do
        result = formatter.format(log_entry)

        expect(result).to include('timestamp:2023-01-01T10:00:00.000Z')
        expect(result).to include('app_id:test_app')
        expect(result).to include('status_code:200')
        expect(result).to include('response_time_ms:45')
        expect(result).to include('request_url:https://example.com/test?param=value')
      end

      it 'separates fields with tabs' do
        result = formatter.format(log_entry)
        fields = result.split("\t")

        expect(fields.length).to eq(8)
        expect(fields[0]).to start_with('timestamp:')
        expect(fields[1]).to start_with('log_version:')
      end

      it 'excludes nil values' do
        log_entry[:user_id] = nil
        result = formatter.format(log_entry)

        expect(result).not_to include('user_id:')
      end

      it 'escapes special characters' do
        log_entry[:user_agent] = "Mozilla/5.0\tTest\nBrowser\rAgent"
        result = formatter.format(log_entry)

        expect(result).to include('user_agent:Mozilla/5.0\\tTest\\nBrowser\\rAgent')
      end

      it 'handles empty string values' do
        log_entry[:referer] = ''
        result = formatter.format(log_entry)

        expect(result).to include('referer:')
      end
    end
  end
end
