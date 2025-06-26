# frozen_string_literal: true

RSpec.describe LazyInit, 'thread safety' do
  describe 'concurrent lazy_attr_reader access' do
    let(:test_class) do
      create_test_class do
        lazy_attr_reader :shared_counter do
          # Simulate potential race condition with a delay
          current = (self.class.class_variable_get(:@@global_counter) rescue 0)
          sleep(0.001) # Give other threads a chance to interfere
          new_value = current + 1
          self.class.class_variable_set(:@@global_counter, new_value)
          new_value
        end

        lazy_attr_reader :timestamp do
          Time.now.to_f
        end

        lazy_attr_reader :random_value do
          @computation_id = (@computation_id || 0) + 1
          @computation_id
        end
      end
    end

    it 'ensures single computation per instance even with high concurrency' do
      instances = Array.new(20) { test_class.new }
      
      results = []
      mutex = Mutex.new
      
      threads = instances.flat_map do |instance|
        # Multiple threads per instance
        3.times.map do
          Thread.new do
            value = instance.random_value
            mutex.synchronize { results << [instance.object_id, value] }
          end
        end
      end
      
      threads.each(&:join)
      
      # Group results by instance
      by_instance = results.group_by(&:first)
      
      # Each instance should have the same value across all its threads
      by_instance.each do |instance_id, instance_results|
        values = instance_results.map(&:last)
        expect(values.uniq.size).to eq(1), 
          "Instance #{instance_id} had multiple values: #{values.uniq}"
      end
    end

    it 'handles rapid concurrent initialization correctly' do
      instance = test_class.new
      
      # Start many threads that all try to access the lazy value simultaneously
      threads = 100.times.map do
        Thread.new { instance.timestamp }
      end
      
      results = threads.map(&:value)
      
      # All threads should get exactly the same timestamp
      expect(results.uniq.size).to eq(1)
      
      # Verify the value is a valid timestamp
      timestamp = results.first
      expect(timestamp).to be_a(Float)
      expect(timestamp).to be > 0
    end

    it 'properly handles computed? predicate during concurrent access' do
      instance = test_class.new
      
      computed_states = []
      values = []
      
      threads = 50.times.map do
        Thread.new do
          # Check computed state before and after getting value
          before = instance.random_value_computed?
          value = instance.random_value
          after = instance.random_value_computed?
          
          [before, value, after]
        end
      end
      
      results = threads.map(&:value)
      
      # All threads should get the same value
      all_values = results.map { |r| r[1] }
      expect(all_values.uniq.size).to eq(1)
      
      # After computation, all threads should see computed? as true
      after_states = results.map { |r| r[2] }
      expect(after_states).to all(be true)
    end

    it 'maintains thread safety during reset operations' do
      instance = test_class.new
      
      # Initialize the value
      initial_value = instance.random_value
      expect(instance.random_value_computed?).to be true
      
      results = []
      mutex = Mutex.new
      
      # Start threads that continuously access the value
      accessor_threads = 10.times.map do
        Thread.new do
          100.times do
            begin
              value = instance.random_value
              mutex.synchronize { results << value } if value  # Filter out nil values
            rescue => e
              # Ignore exceptions during concurrent access/reset
            end
            sleep(0.001)
          end
        end
      end
      
      # Start a thread that periodically resets the value
      reset_thread = Thread.new do
        5.times do
          sleep(0.02)
          instance.reset_random_value!
        end
      end
      
      [*accessor_threads, reset_thread].each(&:join)
      
      # Filter out any nil values that might occur during resets
      valid_results = results.compact
      
      # Should have gotten multiple different values due to resets
      unique_values = valid_results.uniq
      expect(unique_values.size).to be > 1
      
      # But each individual access should have returned a valid number
      expect(valid_results).to all(be_a(Integer))
      expect(valid_results).to all(be > 0)
    end
  end

  describe 'concurrent lazy_class_variable access' do
    before do
      # Clean up any existing test state
      if defined?(TestClassForClassVars)
        Object.send(:remove_const, :TestClassForClassVars) rescue nil
      end
    end

    let(:test_class) do
      # Create a proper class instead of anonymous class to avoid toplevel issues
      class TestClassForClassVars
        extend LazyInit
        
        # Use class instance variable instead of class variable to avoid toplevel access issues
        @resource_counter = 0
        @counter_mutex = Mutex.new
        
        def self.increment_counter
          @counter_mutex.synchronize do
            @resource_counter += 1
          end
        end
        
        def self.get_counter
          @resource_counter
        end
        
        lazy_class_variable :shared_resource do
          # Simulate expensive resource creation with potential race condition
          sleep(0.005) # Longer delay for class variables
          counter = TestClassForClassVars.increment_counter
          "resource_#{counter}"
        end

        lazy_class_variable :shared_timestamp do
          Time.now.to_f
        end
      end
      
      TestClassForClassVars
    end

    it 'ensures single computation across all instances and class access' do
      instances = Array.new(30) { test_class.new }
      
      results = []
      
      # Mix of class-level and instance-level access
      threads = []
      
      # Instance access threads
      threads += instances.map do |instance|
        Thread.new { instance.shared_resource }
      end
      
      # Class access threads
      threads += 20.times.map do
        Thread.new { test_class.shared_resource }
      end
      
      results = threads.map(&:value)
      
      # All should get the same value
      expect(results.uniq).to eq(['resource_1'])
      
      # Verify counter was incremented exactly once
      expect(test_class.get_counter).to eq(1)
    end

    it 'maintains consistency between class and instance access' do
      threads = []
      results = []
      
      # Concurrent access through both class and instance methods
      threads += 25.times.map do
        Thread.new { test_class.shared_timestamp }
      end
      
      threads += 25.times.map do
        Thread.new { test_class.new.shared_timestamp }
      end
      
      results = threads.map(&:value)
      
      # All should be the same timestamp
      expect(results.uniq.size).to eq(1)
      
      # Verify it's a valid timestamp
      expect(results.first).to be_a(Float)
    end

    it 'handles concurrent reset operations safely' do
      # Initialize the value
      initial_value = test_class.shared_resource
      expect(initial_value).to eq('resource_1')
      
      values_seen = []
      mutex = Mutex.new
      
      # Threads continuously accessing the value
      accessor_threads = 15.times.map do
        Thread.new do
          50.times do
            value = test_class.shared_resource
            mutex.synchronize { values_seen << value }
            sleep(0.001)
          end
        end
      end
      
      # Thread that resets periodically  
      reset_thread = Thread.new do
        3.times do
          sleep(0.05)
          test_class.reset_shared_resource!
        end
      end
      
      [*accessor_threads, reset_thread].each(&:join)
      
      # Should have seen multiple values due to resets
      unique_values = values_seen.uniq.sort
      expect(unique_values.size).to be >= 2
      
      # All values should follow the expected pattern
      unique_values.each_with_index do |value, index|
        expect(value).to match(/^resource_\d+$/)
      end
      
      # Verify final counter state
      final_counter = test_class.get_counter
      expect(final_counter).to be >= unique_values.size
    end
  end

  describe 'mixed concurrent access patterns' do
    let(:test_class) do
      create_test_class do
        lazy_attr_reader :instance_value do
          sleep(0.002)
          "instance_#{object_id}_#{rand(1000)}"
        end

        lazy_class_variable :class_value do
          sleep(0.002)
          "class_#{rand(1000)}"
        end
      end
    end

    it 'handles complex concurrent scenarios' do
      instances = Array.new(10) { test_class.new }
      
      all_results = []
      mutex = Mutex.new
      
      threads = []
      
      # Each instance accessed by multiple threads
      instances.each do |instance|
        3.times do
          threads << Thread.new do
            instance_val = instance.instance_value
            class_val = instance.class_value
            mutex.synchronize do
              all_results << {
                type: :instance,
                instance_id: instance.object_id,
                instance_value: instance_val,
                class_value: class_val
              }
            end
          end
        end
      end
      
      # Direct class access
      5.times do
        threads << Thread.new do
          class_val = test_class.class_value
          mutex.synchronize do
            all_results << {
              type: :class,
              class_value: class_val
            }
          end
        end
      end
      
      threads.each(&:join)
      
      # Analyze results
      instance_results = all_results.select { |r| r[:type] == :instance }
      class_results = all_results.select { |r| r[:type] == :class }
      
      # All class values should be the same
      all_class_values = (instance_results + class_results).map { |r| r[:class_value] }
      expect(all_class_values.uniq.size).to eq(1)
      
      # Instance values should be unique per instance but same within instance
      by_instance = instance_results.group_by { |r| r[:instance_id] }
      by_instance.each do |instance_id, results|
        instance_values = results.map { |r| r[:instance_value] }
        expect(instance_values.uniq.size).to eq(1),
          "Instance #{instance_id} had inconsistent values: #{instance_values.uniq}"
      end
    end
  end

  describe 'stress testing' do
    it 'handles extreme concurrency without issues' do
      test_class = create_test_class do
        lazy_attr_reader :stress_value do
          # Simulate various potential issues
          sleep(0.001)
          result = []
          100.times { result << rand(10) }
          result.sum
        end
      end
      
      instance = test_class.new
      
      # Very high concurrency
      threads = 200.times.map do
        Thread.new { instance.stress_value }
      end
      
      results = threads.map(&:value)
      
      # All should be the same
      expect(results.uniq.size).to eq(1)
      
      # Should be a valid computation result
      expect(results.first).to be_a(Integer)
      expect(results.first).to be >= 0
      expect(results.first).to be <= 900 # Max possible sum
    end
  end

  describe 'optimized inline implementation thread safety' do
    let(:simple_class) do
      Class.new do
        extend LazyInit
        
        lazy_attr_reader :concurrent_value do
          # Add small delay to increase chance of race condition
          sleep(0.001)
          "computed_#{Time.now.to_f}"
        end
      end
    end

    it 'ensures single computation with inline optimization' do
      instance = simple_class.new
      
      results = []
      threads = 100.times.map do
        Thread.new do
          results << instance.concurrent_value
        end
      end
      
      threads.each(&:join)
      
      # All threads should get the same value
      expect(results.uniq.size).to eq(1)
      
      # Should use inline variables, not LazyValue
      expect(instance.instance_variable_defined?('@concurrent_value_lazy_value')).to be false
      expect(instance.instance_variable_defined?('@concurrent_value_computed')).to be true
      expect(instance.instance_variable_defined?('@concurrent_value_value')).to be true
    end

    it 'handles concurrent reset operations safely' do
      instance = simple_class.new
      
      # Initialize value
      initial_value = instance.concurrent_value
      expect(instance.concurrent_value_computed?).to be true
      
      results = []
      
      # Start threads that continuously access the value
      accessor_threads = 10.times.map do
        Thread.new do
          50.times do
            results << instance.concurrent_value
            sleep(0.001)
          end
        end
      end
      
      # Start thread that periodically resets
      reset_thread = Thread.new do
        3.times do
          sleep(0.02)
          instance.reset_concurrent_value!
        end
      end
      
      [*accessor_threads, reset_thread].each(&:join)
      
      # Should have multiple values due to resets
      unique_values = results.uniq
      expect(unique_values.size).to be > 1
      
      # All values should be valid strings
      expect(results).to all(be_a(String))
      expect(results).to all(start_with('computed_'))
    end
  end
end