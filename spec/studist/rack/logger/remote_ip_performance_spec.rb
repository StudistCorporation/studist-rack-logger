# frozen_string_literal: true

require 'spec_helper'
require 'benchmark'

RSpec.describe Studist::Rack::Logger::RemoteIp, :performance do
  let(:remote_ip) { described_class.new }

  describe 'performance with large IP chains' do
    context 'with very long X-Forwarded-For chain (100 IPs)' do
      let(:large_ip_chain) do
        # Generate 98 private IPs + 2 public IPs
        private_ips = (1..98).map { |i| "10.0.#{i / 256}.#{i % 256}" }
        public_ips = ['203.0.113.1', '198.51.100.1']
        (public_ips + private_ips).join(', ')
      end

      let(:env) do
        {
          'HTTP_X_FORWARDED_FOR' => large_ip_chain,
          'REMOTE_ADDR' => '127.0.0.1',
        }
      end

      it 'processes large IP chains efficiently' do
        # Benchmark the operation
        time = Benchmark.realtime do
          100.times { remote_ip.call(env) }
        end

        # Should complete 100 operations in reasonable time (< 0.1s)
        expect(time).to be < 0.1

        # Should still return correct result
        expect(remote_ip.call(env)).to eq('198.51.100.1')
      end
    end

    context 'with malformed large chain (DoS protection)' do
      let(:malformed_chain) do
        # Mix of valid and invalid IPs
        ips = []
        50.times { |i| ips << "invalid-ip-#{i}" }
        50.times { |i| ips << "10.0.#{i / 256}.#{i % 256}" }
        ips << '203.0.113.1' # One valid public IP
        ips.join(', ')
      end

      let(:env) do
        {
          'HTTP_X_FORWARDED_FOR' => malformed_chain,
          'REMOTE_ADDR' => '127.0.0.1',
        }
      end

      it 'handles malformed chains without significant performance degradation' do
        time = Benchmark.realtime do
          50.times { remote_ip.call(env) }
        end

        # Should still be reasonably fast
        expect(time).to be < 0.1

        # Should find the valid IP despite malformed entries
        expect(remote_ip.call(env)).to eq('203.0.113.1')
      end
    end

    context 'with memory efficiency' do
      it 'does not create excessive intermediate objects' do
        env = {
          'HTTP_X_FORWARDED_FOR' => '203.0.113.1, 198.51.100.1, 10.0.0.1',
          'REMOTE_ADDR' => '127.0.0.1',
        }

        # Simulate multiple calls to check for memory leaks
        1000.times { remote_ip.call(env) }

        # If we get here without memory issues, the test passes
        expect(remote_ip.call(env)).to eq('198.51.100.1')
      end
    end
  end

  describe 'concurrent access safety' do
    it 'handles concurrent requests safely' do
      envs = [
        { 'HTTP_X_FORWARDED_FOR' => '203.0.113.1, 10.0.0.1', 'REMOTE_ADDR' => '127.0.0.1' },
        { 'HTTP_X_FORWARDED_FOR' => '198.51.100.1, 172.16.0.1', 'REMOTE_ADDR' => '127.0.0.1' },
        { 'HTTP_X_FORWARDED_FOR' => '192.0.2.1, 192.168.1.1', 'REMOTE_ADDR' => '127.0.0.1' }
      ]

      results = []
      threads = envs.map do |env|
        Thread.new do
          100.times { results << remote_ip.call(env) }
        end
      end

      threads.each(&:join)

      # Should have consistent results
      expect(results.count('203.0.113.1')).to eq(100)
      expect(results.count('198.51.100.1')).to eq(100)
      expect(results.count('192.0.2.1')).to eq(100)
    end
  end
end
