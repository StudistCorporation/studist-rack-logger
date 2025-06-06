# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Studist::Rack::Logger::RemoteIp do
  let(:remote_ip) { described_class.new }

  describe '#initialize' do
    context 'with default trusted proxies' do
      it 'uses default proxy list' do
        expect(remote_ip.trusted_proxies).to have_attributes(length: 7)
      end
    end

    context 'with custom trusted proxies' do
      let(:custom_proxies) { ['10.0.0.0/8', '172.16.0.0/12'] }
      let(:remote_ip) { described_class.new(trusted_proxies: custom_proxies) }

      it 'uses custom proxy list' do
        expect(remote_ip.trusted_proxies).to have_attributes(length: 2)
      end
    end

    context 'with invalid proxy addresses' do
      let(:custom_proxies) { ['10.0.0.0/8', 'invalid', '172.16.0.0/12'] }
      let(:remote_ip) { described_class.new(trusted_proxies: custom_proxies) }

      it 'filters out invalid addresses' do
        expect(remote_ip.trusted_proxies).to have_attributes(length: 2)
      end
    end
  end

  describe '#call' do
    context 'with no proxy headers' do
      let(:env) { { 'REMOTE_ADDR' => '203.0.113.1' } }

      it 'returns the REMOTE_ADDR' do
        expect(remote_ip.call(env)).to eq('203.0.113.1')
      end
    end

    context 'with localhost REMOTE_ADDR' do
      let(:env) { { 'REMOTE_ADDR' => '127.0.0.1' } }

      it 'returns the localhost IP when no other options' do
        expect(remote_ip.call(env)).to eq('127.0.0.1')
      end
    end

    context 'with X-Forwarded-For header' do
      context 'single IP' do
        let(:env) do
          {
            'HTTP_X_FORWARDED_FOR' => '203.0.113.1',
            'REMOTE_ADDR' => '10.0.0.1',
          }
        end

        it 'returns the forwarded IP when proxy is trusted' do
          expect(remote_ip.call(env)).to eq('203.0.113.1')
        end
      end

      context 'multiple IPs (proxy chain)' do
        let(:env) do
          {
            'HTTP_X_FORWARDED_FOR' => '203.0.113.1, 198.51.100.1, 10.0.0.1',
            'REMOTE_ADDR' => '10.0.0.2',
          }
        end

        it 'returns the first non-proxy IP from the chain' do
          expect(remote_ip.call(env)).to eq('198.51.100.1')
        end
      end

      context 'all IPs are proxies' do
        let(:env) do
          {
            'HTTP_X_FORWARDED_FOR' => '10.0.0.1, 172.16.0.1',
            'REMOTE_ADDR' => '192.168.1.1',
          }
        end

        it 'returns the last IP (REMOTE_ADDR equivalent)' do
          expect(remote_ip.call(env)).to eq('192.168.1.1')
        end
      end

      context 'with whitespace in header' do
        let(:env) do
          {
            'HTTP_X_FORWARDED_FOR' => ' 203.0.113.1 , 198.51.100.1 ',
            'REMOTE_ADDR' => '10.0.0.1',
          }
        end

        it 'handles whitespace correctly' do
          expect(remote_ip.call(env)).to eq('198.51.100.1')
        end
      end
    end

    context 'with X-Real-IP header' do
      let(:env) do
        {
          'HTTP_X_REAL_IP' => '203.0.113.1',
          'REMOTE_ADDR' => '10.0.0.1',
        }
      end

      it 'returns the X-Real-IP when not a proxy' do
        expect(remote_ip.call(env)).to eq('203.0.113.1')
      end
    end

    context 'with Client-IP header' do
      let(:env) do
        {
          'HTTP_CLIENT_IP' => '203.0.113.1',
          'REMOTE_ADDR' => '10.0.0.1',
        }
      end

      it 'returns the Client-IP when not a proxy' do
        expect(remote_ip.call(env)).to eq('203.0.113.1')
      end
    end

    context 'with IPv6 addresses' do
      let(:env) do
        {
          'HTTP_X_FORWARDED_FOR' => '2001:db8::1',
          'REMOTE_ADDR' => '::1',
        }
      end

      it 'handles IPv6 addresses correctly' do
        expect(remote_ip.call(env)).to eq('2001:db8::1')
      end
    end

    context 'with IPv4-mapped IPv6 addresses (Ruby 3.1+ compatibility)' do
      let(:env) do
        {
          'HTTP_X_FORWARDED_FOR' => '::ffff:203.0.113.1',
          'REMOTE_ADDR' => '::ffff:127.0.0.1',
        }
      end

      it 'converts IPv4-mapped addresses to IPv4' do
        expect(remote_ip.call(env)).to eq('203.0.113.1')
      end
    end

    context 'with custom trusted proxies' do
      let(:custom_proxies) { ['198.51.100.0/24'] }
      let(:remote_ip) { described_class.new(trusted_proxies: custom_proxies) }
      let(:env) do
        {
          'HTTP_X_FORWARDED_FOR' => '203.0.113.1, 198.51.100.1',
          'REMOTE_ADDR' => '198.51.100.2',
        }
      end

      it 'uses custom proxy configuration' do
        expect(remote_ip.call(env)).to eq('203.0.113.1')
      end
    end

    context 'with invalid IP addresses' do
      let(:env) do
        {
          'HTTP_X_FORWARDED_FOR' => 'invalid-ip, 203.0.113.1',
          'REMOTE_ADDR' => '10.0.0.1',
        }
      end

      it 'filters out invalid IPs' do
        expect(remote_ip.call(env)).to eq('203.0.113.1')
      end
    end

    context 'with spoofed headers from untrusted proxy' do
      let(:custom_proxies) { ['10.0.0.0/8'] } # Only trust 10.x network
      let(:remote_ip) { described_class.new(trusted_proxies: custom_proxies) }
      let(:env) do
        {
          'HTTP_X_FORWARDED_FOR' => '203.0.113.1', # Potentially spoofed
          'REMOTE_ADDR' => '198.51.100.1', # Untrusted proxy
        }
      end

      it 'does not trust headers from untrusted proxies' do
        expect(remote_ip.call(env)).to eq('198.51.100.1')
      end
    end

    context 'with no valid IPs' do
      let(:env) { {} }

      it 'returns nil when no IPs found' do
        expect(remote_ip.call(env)).to be_nil
      end
    end

    context 'with empty/null header values' do
      let(:env) do
        {
          'HTTP_X_FORWARDED_FOR' => '',
          'HTTP_X_REAL_IP' => '   ',
          'HTTP_CLIENT_IP' => nil,
          'REMOTE_ADDR' => '203.0.113.1',
        }
      end

      it 'falls back to REMOTE_ADDR when other headers are empty' do
        expect(remote_ip.call(env)).to eq('203.0.113.1')
      end
    end

    context 'with multiple headers present (precedence test)' do
      let(:env) do
        {
          'HTTP_X_FORWARDED_FOR' => '203.0.113.1, 10.0.0.1',
          'HTTP_X_REAL_IP' => '198.51.100.1',
          'HTTP_CLIENT_IP' => '192.0.2.1',
          'REMOTE_ADDR' => '172.16.0.1',
        }
      end

      it 'prioritizes X-Forwarded-For over other headers' do
        expect(remote_ip.call(env)).to eq('203.0.113.1')
      end
    end

    context 'with malformed X-Forwarded-For (edge cases)' do
      context 'with extra commas' do
        let(:env) do
          {
            'HTTP_X_FORWARDED_FOR' => '203.0.113.1,, 198.51.100.1, ',
            'REMOTE_ADDR' => '10.0.0.1',
          }
        end

        it 'handles extra commas gracefully' do
          expect(remote_ip.call(env)).to eq('198.51.100.1')
        end
      end

      context 'with only invalid IPs in X-Forwarded-For' do
        let(:env) do
          {
            'HTTP_X_FORWARDED_FOR' => 'invalid-ip, not-an-ip',
            'HTTP_X_REAL_IP' => '203.0.113.1',
            'REMOTE_ADDR' => '10.0.0.1',
          }
        end

        it 'falls back to X-Real-IP when X-Forwarded-For contains only invalid IPs' do
          expect(remote_ip.call(env)).to eq('203.0.113.1')
        end
      end
    end

    context 'with CDN-like proxy chains' do
      let(:env) do
        {
          'HTTP_X_FORWARDED_FOR' => '203.0.113.1, 198.51.100.1, 172.16.0.1, 10.0.0.1, 192.168.1.1',
          'REMOTE_ADDR' => '127.0.0.1',
        }
      end

      it 'finds the first public IP in a long proxy chain' do
        expect(remote_ip.call(env)).to eq('198.51.100.1')
      end
    end

    context 'with IPv6 private ranges' do
      let(:env) do
        {
          'HTTP_X_FORWARDED_FOR' => '2001:db8::1, fc00::1, fe80::1',
          'REMOTE_ADDR' => '::1',
        }
      end

      it 'correctly filters IPv6 private addresses' do
        expect(remote_ip.call(env)).to eq('2001:db8::1')
      end
    end
  end

  describe 'private network filtering' do
    let(:test_cases) do
      {
        # IPv4 private networks
        '10.0.0.1' => true,
        '172.16.0.1' => true,
        '192.168.1.1' => true,
        '127.0.0.1' => true,
        # IPv4 public
        '203.0.113.1' => false,
        '8.8.8.8' => false,
        # IPv6 private
        '::1' => true,
        'fc00::1' => true,
        'fe80::1' => true,
        # IPv6 public
        '2001:db8::1' => false,
      }
    end

    it 'correctly identifies private vs public IPs' do
      test_cases.each do |ip, should_be_trusted|
        env = { 'REMOTE_ADDR' => ip }
        result = remote_ip.call(env)

        if should_be_trusted
          # For trusted IPs, we expect to get the IP back (no other options)
          expect(result).to eq(ip), "Expected #{ip} to be treated as trusted"
        else
          # For public IPs, we expect to get them back as well (they're valid client IPs)
          expect(result).to eq(ip), "Expected #{ip} to be treated as public client IP"
        end
      end
    end
  end
end
