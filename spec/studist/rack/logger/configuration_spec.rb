# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Studist::Rack::Logger::Configuration do
  let(:config) { described_class.new }

  describe '#initialize' do
    it 'sets default values' do
      expect(config.app_id).to eq('unknown')
      expect(config.format).to eq(:json)
      expect(config.log_version).to eq('1.0.0')
      expect(config.sampling_rate).to eq(1.0)
      expect(config.error_sampling_rate).to eq(1.0)
      expect(config.trusted_proxies).to be_nil
      expect(config.extractors).to be_empty
      expect(config.filters).to be_empty
      expect(config.skip_paths).to be_empty
      expect(config.skip_conditions).to be_empty
    end
  end

  describe '#extractor' do
    it 'registers an extractor proc' do
      config.extractor(:user_id) { |env, _req| env['user.id'] }

      expect(config.extractors[:user_id]).to be_a(Proc)
    end

    it 'raises error when no block given' do
      expect { config.extractor(:user_id) }.to raise_error(ArgumentError, 'Block is required for extractor')
    end
  end

  describe '#filter' do
    it 'adds a filter proc' do
      config.filter { |context| context[:status] == 200 }

      expect(config.filters.size).to eq(1)
      expect(config.filters.first).to be_a(Proc)
    end

    it 'raises error when no block given' do
      expect { config.filter }.to raise_error(ArgumentError, 'Block is required for filter')
    end
  end

  describe '#skip_paths=' do
    it 'sets skip paths array' do
      config.skip_paths = ['/health', '/metrics']

      expect(config.skip_paths).to eq(['/health', '/metrics'])
    end

    it 'converts single string to array' do
      config.skip_paths = '/health'

      expect(config.skip_paths).to eq(['/health'])
    end
  end

  describe '#skip_if' do
    it 'adds a skip condition' do
      config.skip_if { |context| context[:status] == 200 }

      expect(config.skip_conditions.size).to eq(1)
      expect(config.skip_conditions.first).to be_a(Proc)
    end

    it 'raises error when no block given' do
      expect { config.skip_if }.to raise_error(ArgumentError, 'Block is required for skip_if')
    end
  end

  describe '#validate!' do
    context 'with valid configuration' do
      it 'does not raise error' do
        config.format = :json
        config.sampling_rate = 0.5
        config.error_sampling_rate = 1.0
        config.extractor(:user_id) { |env, _req| env['user.id'] }

        expect { config.validate! }.not_to raise_error
      end
    end

    context 'with invalid format' do
      it 'raises ArgumentError' do
        config.format = :invalid

        expect { config.validate! }.to raise_error(ArgumentError, /Unsupported format: invalid/)
      end
    end

    context 'with invalid sampling rate' do
      it 'raises ArgumentError for sampling_rate > 1.0' do
        config.sampling_rate = 1.5

        expect { config.validate! }.to raise_error(ArgumentError, /sampling_rate must be a number between 0.0 and 1.0/)
      end

      it 'raises ArgumentError for negative sampling_rate' do
        config.sampling_rate = -0.1

        expect { config.validate! }.to raise_error(ArgumentError, /sampling_rate must be a number between 0.0 and 1.0/)
      end

      it 'raises ArgumentError for non-numeric sampling_rate' do
        config.sampling_rate = 'invalid'

        expect { config.validate! }.to raise_error(ArgumentError, /sampling_rate must be a number between 0.0 and 1.0/)
      end
    end

    context 'with invalid extractor' do
      it 'raises ArgumentError for non-callable extractor' do
        config.instance_variable_get(:@extractors)[:user_id] = 'not_callable'

        expect { config.validate! }.to raise_error(ArgumentError, /Extractor user_id must respond to call/)
      end
    end
  end

  describe '#to_middleware_options' do
    it 'converts configuration to middleware options hash' do
      config.app_id = 'test-app'
      config.format = :ltsv
      config.sampling_rate = 0.5
      config.trusted_proxies = ['10.0.0.0/8']
      config.extractor(:user_id) { |env, _req| env['user.id'] }
      config.extractor(:user_group_id) { |env, _req| env['user.group'] }

      options = config.to_middleware_options

      expect(options[:app_id]).to eq('test-app')
      expect(options[:format]).to eq(:ltsv)
      expect(options[:sampling_rate]).to eq(0.5)
      expect(options[:trusted_proxies]).to eq(['10.0.0.0/8'])
      expect(options[:user_id_extractor]).to be_a(Proc)
      expect(options[:user_group_id_extractor]).to be_a(Proc)
    end

    it 'validates configuration before conversion' do
      config.format = :invalid

      expect { config.to_middleware_options }.to raise_error(ArgumentError, /Unsupported format/)
    end
  end

  describe '#should_log?' do
    let(:context) do
      {
        request_path: '/api/users',
        status: 200,
        error: false,
      }
    end

    context 'with skip paths' do
      before { config.skip_paths = ['/health', '/metrics'] }

      it 'returns false for matching skip path' do
        context[:request_path] = '/health'

        expect(config.should_log?(context)).to be false
      end

      it 'returns true for non-matching path' do
        expect(config.should_log?(context)).to be true
      end
    end

    context 'with skip conditions' do
      before do
        config.skip_if { |ctx| ctx[:status] == 200 && ctx[:request_path].start_with?('/api') }
      end

      it 'returns false when condition matches' do
        expect(config.should_log?(context)).to be false
      end

      it 'returns true when condition does not match' do
        context[:status] = 404

        expect(config.should_log?(context)).to be true
      end
    end

    context 'with sampling' do
      before { config.sampling_rate = 0.0 }

      it 'returns false when sampling rate is 0' do
        expect(config.should_log?(context)).to be false
      end

      it 'uses error sampling rate for errors' do
        config.error_sampling_rate = 1.0
        context[:error] = true

        expect(config.should_log?(context)).to be true
      end
    end

    context 'with filters' do
      before do
        config.filter { |ctx| ctx[:status] != 404 }
      end

      it 'returns false when filter rejects' do
        context[:status] = 404

        expect(config.should_log?(context)).to be false
      end

      it 'returns true when filter passes' do
        expect(config.should_log?(context)).to be true
      end
    end
  end
end
