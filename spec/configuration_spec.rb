# frozen_string_literal: true

RSpec.describe LazyInit::Configuration do
  after do
    # Reset configuration after each test
    LazyInit.instance_variable_set(:@configuration, nil)
  end

  it 'has default values' do
    config = LazyInit::Configuration.new

    # expect(config.debug).to be false
    expect(config.default_timeout).to be_nil
    # expect(config.track_performance).to be false
    # expect(config.enable_warnings).to be true
    expect(config.max_lazy_once_entries).to eq(1000)
    expect(config.lazy_once_ttl).to be_nil
  end

  it 'allows configuration through block' do
    LazyInit.configure do |config|
      # config.debug = true
      config.default_timeout = 30
      config.max_lazy_once_entries = 500
    end

    config = LazyInit.configuration
    # expect(config.debug).to be true
    expect(config.default_timeout).to eq(30)
    expect(config.max_lazy_once_entries).to eq(500)
  end

  it 'uses configured default timeout' do
    LazyInit.configure do |config|
      config.default_timeout = 5
    end

    test_class = Class.new do
      extend LazyInit

      lazy_attr_reader :slow_operation do
        sleep(0.1)
        'result'
      end
    end

    instance = test_class.new

    # Should use configured timeout
    expect(instance.slow_operation).to eq('result')
  end

  it 'uses configured max_lazy_once_entries' do
    LazyInit.configure do |config|
      config.max_lazy_once_entries = 3
    end

    test_class = Class.new { include LazyInit }
    instance = test_class.new

    # Create more entries than configured max
    5.times do |i|
      instance.define_singleton_method("method_#{i}") do
        lazy_once { "value_#{i}" }
      end
      instance.send("method_#{i}")
    end

    stats = instance.lazy_once_statistics
    expect(stats[:total_entries]).to be <= 3
  end
end
