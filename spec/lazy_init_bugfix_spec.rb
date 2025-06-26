# frozen_string_literal: true

RSpec.describe 'LazyInit Bug Fixes' do
  describe 'thread-safe class mutex' do
    it 'prevents race conditions in class mutex creation' do
      test_classes = []
      
      # Create many classes simultaneously that extend LazyInit
      threads = 50.times.map do
        Thread.new do
          test_class = Class.new { extend LazyInit }
          test_classes << test_class
        end
      end
      
      threads.each(&:join)
      
      # All should have their own mutex
      mutexes = test_classes.map { |klass| klass.instance_variable_get(:@lazy_init_class_mutex) }
      expect(mutexes).to all(be_a(Mutex))
      expect(mutexes.uniq.size).to eq(test_classes.size) # Each class has its own mutex
    end
  end

  describe 'lazy_once memory management' do
    let(:test_class) { Class.new { include LazyInit } }
    
    it 'limits cache size' do
      instance = test_class.new
      
      # Create more entries than max_entries
      15.times do |i|
        instance.define_singleton_method("method_#{i}") do
          lazy_once(max_entries: 10) { "value_#{i}" }
        end
        instance.send("method_#{i}")
      end
      
      info = instance.lazy_once_info
      expect(info.size).to be <= 10
    end
    
    it 'respects TTL' do
      instance = test_class.new
      
      def instance.test_method
        lazy_once(ttl: 0.1) { Time.now.to_f }
      end
      
      first_value = instance.test_method
      sleep(0.15) # Wait for TTL to expire
      
      # Trigger cleanup by calling lazy_once again
      def instance.test_method2
        lazy_once(ttl: 0.1) { 'trigger_cleanup' }
      end
      instance.test_method2
      
      second_value = instance.test_method
      expect(second_value).not_to eq(first_value) # Should be recomputed
    end
  end

  describe 'input validation' do
    let(:test_class) { Class.new { extend LazyInit } }
    
    it 'validates attribute names' do
      expect { test_class.lazy_attr_reader(nil) { 'test' } }
        .to raise_error(LazyInit::InvalidAttributeNameError, 'Attribute name cannot be nil')
        
      expect { test_class.lazy_attr_reader('') { 'test' } }
        .to raise_error(LazyInit::InvalidAttributeNameError, 'Attribute name cannot be empty')
        
      expect { test_class.lazy_attr_reader('123invalid') { 'test' } }
        .to raise_error(LazyInit::InvalidAttributeNameError, /Invalid attribute name/)
        
      expect { test_class.lazy_attr_reader('valid_name') { 'test' } }
        .not_to raise_error
    end
  end

  describe 'timeout support' do
    let(:test_class) do
      Class.new do
        extend LazyInit
        
        lazy_attr_reader :quick_value, timeout: 1 do
          'quick'
        end
        
        lazy_attr_reader :slow_value, timeout: 0.1 do
          sleep(0.2)
          'slow'
        end
      end
    end
    
    it 'allows quick computations' do
      instance = test_class.new
      expect(instance.quick_value).to eq('quick')
    end
    
    it 'times out slow computations' do
      instance = test_class.new
      expect { instance.slow_value }.to raise_error(LazyInit::TimeoutError, /timed out after 0.1s/)
    end
    
    it 'maintains timeout error state' do
      instance = test_class.new
      expect { instance.slow_value }.to raise_error(LazyInit::TimeoutError)
      expect { instance.slow_value }.to raise_error(LazyInit::TimeoutError) # Same error
      expect(instance.slow_value_computed?).to be false
    end
  end
end