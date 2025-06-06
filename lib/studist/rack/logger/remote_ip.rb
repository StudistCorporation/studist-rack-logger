# frozen_string_literal: true

require 'ipaddr'

module Studist
  module Rack
    module Logger
      # Secure remote IP extraction with trusted proxy filtering.
      #
      # This class provides Rails-like functionality for determining the real client IP
      # address from requests that may have passed through multiple proxies, while
      # protecting against IP spoofing attacks.
      #
      # Header Processing Priority:
      # 1. X-Forwarded-For (highest priority, supports proxy chains)
      # 2. X-Real-IP (single IP fallback)
      # 3. Client-IP (legacy support)
      # 4. REMOTE_ADDR (direct connection fallback)
      #
      # Security Features:
      # - Validates all IP addresses before processing
      # - Filters trusted proxy ranges (RFC 1918 + IPv6 private)
      # - Handles IPv4-mapped IPv6 addresses (Ruby 3.1+ compatibility)
      # - Protects against IP spoofing from untrusted proxies
      #
      # Based on Rails' ActionDispatch::RemoteIp but optimized for logging purposes.
      class RemoteIp
        # Default trusted proxy IP ranges (private networks)
        DEFAULT_TRUSTED_PROXIES = [
          '127.0.0.0/8',    # localhost IPv4
          '10.0.0.0/8',     # private class A
          '172.16.0.0/12',  # private class B
          '192.168.0.0/16', # private class C
          '::1/128',        # localhost IPv6
          'fc00::/7',       # private IPv6
          'fe80::/10' # link-local IPv6
        ].freeze

        attr_reader :trusted_proxies

        # Initialize with trusted proxy configuration
        #
        # @param trusted_proxies [Array<String>, nil] Array of IP ranges in CIDR notation
        #   If nil, uses DEFAULT_TRUSTED_PROXIES
        def initialize(trusted_proxies: nil)
          @trusted_proxies = build_trusted_proxies(trusted_proxies)
        end

        # Extract the real client IP from the Rack environment
        #
        # @param env [Hash] Rack environment hash
        # @return [String, nil] The real client IP address, or nil if none found
        def call(env)
          remote_addr = extract_remote_addr(env)
          return remote_addr&.to_s unless should_process_headers?(remote_addr)

          # Try forwarded headers in order of preference
          process_forwarded_headers(env, remote_addr) || remote_addr&.to_s
        end

        private

          def extract_remote_addr(env)
            normalize_ip(env['REMOTE_ADDR']) if env['REMOTE_ADDR']
          end

          def should_process_headers?(remote_addr)
            remote_addr && trusted_proxy?(remote_addr)
          end

          def process_forwarded_headers(env, remote_addr)
            process_x_forwarded_for(env, remote_addr) ||
              process_fallback_headers(env, remote_addr)
          end

          def process_x_forwarded_for(env, remote_addr)
            forwarded_ips = extract_forwarded_for_ips(env['HTTP_X_FORWARDED_FOR'])
            return nil if forwarded_ips.empty?

            # Add REMOTE_ADDR to the end of the chain for complete processing
            all_ips = forwarded_ips + [remote_addr]
            filter_proxies(all_ips, remote_addr)
          end

          def process_fallback_headers(env, remote_addr)
            fallback_headers = %w[HTTP_X_REAL_IP HTTP_CLIENT_IP]
            fallback_headers.each do |header|
              result = process_single_header(env, header, remote_addr)
              return result if result
            end
            nil
          end

          def process_single_header(env, header, remote_addr)
            value = env[header]
            return nil if value.nil? || value.strip.empty?

            ip = normalize_ip(value.strip)
            filter_proxies([ip, remote_addr], remote_addr) if ip
          end

          def build_trusted_proxies(custom_proxies)
            proxy_list = custom_proxies || DEFAULT_TRUSTED_PROXIES
            proxy_list.map { |proxy| normalize_proxy(proxy) }.compact
          end

          def normalize_proxy(proxy)
            case proxy
            when String
              IPAddr.new(proxy)
            when IPAddr
              proxy
            end
          rescue IPAddr::InvalidAddressError
            nil
          end

          def extract_forwarded_for_ips(forwarded_for_value)
            return [] if forwarded_for_value.nil? || forwarded_for_value.strip.empty?

            # Parse comma-separated IPs and normalize them
            parse_forwarded_for(forwarded_for_value)
              .map { |ip| normalize_ip(ip) }
              .compact
          end

          def parse_forwarded_for(header_value)
            header_value.split(',').map(&:strip).reject(&:empty?)
          end

          def normalize_ip(ip_string)
            # Handle IPv4-mapped IPv6 addresses for Ruby 3.1+ compatibility
            normalized = ip_string.strip

            # Convert IPv4-mapped IPv6 to IPv4 if possible
            normalized = ::Regexp.last_match(1) if normalized =~ /\A::ffff:(\d+\.\d+\.\d+\.\d+)\z/i

            IPAddr.new(normalized)
          rescue IPAddr::InvalidAddressError
            nil
          end

          def filter_proxies(ip_addrs, fallback_ip = nil)
            # Work backwards through the IP chain to find the first non-proxy IP
            ip_addrs.reverse.each do |ip_addr|
              next if trusted_proxy?(ip_addr)

              return ip_addr.to_s
            end

            # If all IPs are proxies, return the fallback (usually REMOTE_ADDR)
            fallback_ip&.to_s || ip_addrs.last&.to_s
          end

          def trusted_proxy?(ip_addr)
            @trusted_proxies.any? { |proxy| proxy.include?(ip_addr) }
          rescue StandardError
            # If there's any error in comparison, treat as untrusted for safety
            false
          end
      end
    end
  end
end
