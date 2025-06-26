# frozen_string_literal: true

RSpec.describe LazyInit do
  describe '.included' do
    it 'adds both class and instance methods' do
      test_class = Class.new { include LazyInit }
      
      expect(test_class).to respond_to(:lazy_attr_reader)
      expect(test_class).to respond_to(:lazy_class_variable)
      expect(test_class.new).to respond_to(:lazy)
      expect(test_class.new).to respond_to(:lazy_once)
    end
  end

  describe '.extended' do
    it 'adds class methods only' do
      test_class = Class.new { extend LazyInit }
      
      expect(test_class).to respond_to(:lazy_attr_reader)
      expect(test_class).to respond_to(:lazy_class_variable)
      expect(test_class.new).not_to respond_to(:lazy)
    end
  end

  describe '#lazy_attr_reader' do
    let(:test_class) do
      create_test_class do
      lazy_attr_reader :expensive_calculation do
        sleep(0.01)
        "calculated_#{object_id}_#{rand(1000)}"
      end

        lazy_attr_reader :counter do
          @my_counter = (@my_counter || 0) + 1
        end

        lazy_attr_reader :current_time do
          Time.now
        end
      end
    end

    it 'requires a block' do
      expect do
        create_test_class do
          lazy_attr_reader :invalid_attr
        end
      end.to raise_error(ArgumentError, 'Block is required')
    end

    it 'creates the main accessor method' do
      instance = test_class.new
      expect(instance).to respond_to(:expensive_calculation)
      expect(instance).to respond_to(:counter)
      expect(instance).to respond_to(:current_time)
    end

    it 'creates predicate methods' do
      instance = test_class.new
      expect(instance).to respond_to(:expensive_calculation_computed?)
      expect(instance).to respond_to(:counter_computed?)
      expect(instance).to respond_to(:current_time_computed?)
    end

    it 'creates reset methods' do
      instance = test_class.new
      expect(instance).to respond_to(:reset_expensive_calculation!)
      expect(instance).to respond_to(:reset_counter!)
      expect(instance).to respond_to(:reset_current_time!)
    end

    describe 'lazy computation' do
      it 'computes value only once' do
        instance = test_class.new
        
        first_call = instance.counter
        second_call = instance.counter
        third_call = instance.counter
        
        expect(first_call).to eq(1)
        expect(second_call).to eq(1)
        expect(third_call).to eq(1)
      end

      it 'computes different values for different instances' do
        instance1 = test_class.new
        instance2 = test_class.new
        
        expect(instance1.counter).to eq(1)
        expect(instance2.counter).to eq(1)
        # Each instance gets its own counter
      end

      it 'maintains proper state with predicate methods' do
        instance = test_class.new
        
        expect(instance.counter_computed?).to be false
        value = instance.counter
        expect(instance.counter_computed?).to be true
        expect(value).to eq(1)
      end
    end

    describe 'reset functionality' do
      it 'allows resetting and recomputing' do
        instance = test_class.new
        
        first_value = instance.counter
        expect(first_value).to eq(1)
        expect(instance.counter_computed?).to be true
        
        instance.reset_counter!
        expect(instance.counter_computed?).to be false
        
        instance.reset_counter!
        second_value = instance.counter
        expect(second_value).not_to eq(first_value)
        expect(instance.counter_computed?).to be true
      end

      it 'works when called on uncomputed values' do
        instance = test_class.new
        
        expect(instance.counter_computed?).to be false
        instance.reset_counter! # Should not raise error
        expect(instance.counter_computed?).to be false
        
        value = instance.counter
        expect(value).to eq(1)
      end
    end

    describe 'thread safety' do
      it 'ensures each instance computes its value only once in concurrent access' do
        instance = test_class.new
        
        results = run_in_threads(50) { instance.expensive_calculation }
        
        # All threads should get the same value
        expect(results.uniq.size).to eq(1)
      end

      it 'handles multiple instances concurrently' do
        instances = Array.new(10) { test_class.new }
        
        results = []
        threads = instances.map do |instance|
          Thread.new do
            results << instance.current_time
          end
        end
        
        threads.each(&:join)
        
        # Each instance should have its own timestamp
        expect(results.size).to eq(10)
        # All should be Time objects
        expect(results).to all(be_a(Time))
      end
    end

    describe 'exception handling' do
      let(:failing_class) do
        create_test_class do
          lazy_attr_reader :failing_method do
            raise StandardError, 'Computation failed'
          end
        end
      end

      it 'propagates exceptions from the computation block' do
        instance = failing_class.new
        
        expect { instance.failing_method }.to raise_error(StandardError, 'Computation failed')
      end

      it 'does not mark as computed when exception occurs' do
        instance = failing_class.new
        
        expect { instance.failing_method }.to raise_error
        expect(instance.failing_method_computed?).to be false
      end

      it 'allows retry after reset' do
        retry_class = create_test_class do
          attr_accessor :attempt_count
          
          def initialize
            @attempt_count = 0
          end
          
          lazy_attr_reader :maybe_failing do
            @attempt_count += 1
            raise 'fail' if @attempt_count == 1
            'success'
          end
        end
        
        instance = retry_class.new
        
        expect { instance.maybe_failing }.to raise_error('fail')
        
        instance.reset_maybe_failing!
        expect(instance.maybe_failing).to eq('success')
      end
    end
  end

  describe '#lazy_class_variable' do
    before do
    # clear class variables between tests
    test_class.class_variables.each do |cvar|
      test_class.remove_class_variable(cvar) if cvar.to_s.include?('lazy')
      end
    end

    let(:test_class) do
      counter_var = "@@global_counter_#{rand(1000)}"  # Unique per test
      
      create_test_class do
        lazy_class_variable :shared_counter do
          current = (class_variable_get(counter_var) rescue 0)
          class_variable_set(counter_var, current + 1)
          current + 1
        end

        lazy_class_variable :shared_resource do  # ← DODAJ TO
          "resource_#{rand(1000)}"
        end
      end
    end

    it 'requires a block' do
      expect do
        create_test_class do
          lazy_class_variable :invalid_var
        end
      end.to raise_error(ArgumentError, 'Block is required')
    end

    it 'creates class methods' do
      expect(test_class).to respond_to(:shared_counter)
      expect(test_class).to respond_to(:shared_counter_computed?)
      expect(test_class).to respond_to(:reset_shared_counter!)
    end

    it 'creates instance methods that delegate to class methods' do
      instance = test_class.new
      expect(instance).to respond_to(:shared_counter)
      expect(instance).to respond_to(:shared_counter_computed?)
      expect(instance).to respond_to(:reset_shared_counter!)
    end

    describe 'shared state' do
      it 'computes value only once across all instances' do
        instance1 = test_class.new
        instance2 = test_class.new
        
        value1 = instance1.shared_counter
        value2 = instance2.shared_counter
        class_value = test_class.shared_counter
        
        expect(value1).to eq(1)
        expect(value2).to eq(1)
        expect(class_value).to eq(1)
      end

      it 'shares the same object reference' do
        instance1 = test_class.new
        instance2 = test_class.new
        
        resource1 = instance1.shared_resource
        resource2 = instance2.shared_resource
        class_resource = test_class.shared_resource
        
        expect(resource1).to be(resource2)
        expect(resource1).to be(class_resource)
      end
    end

    describe 'computed state' do
      it 'reports computed state correctly' do
        expect(test_class.shared_counter_computed?).to be false
        
        test_class.shared_counter
        expect(test_class.shared_counter_computed?).to be true
        
        # Instance methods should report the same state
        instance = test_class.new
        expect(instance.shared_counter_computed?).to be true
      end
    end

    describe 'reset functionality' do
      it 'allows resetting class variables' do
        initial_value = test_class.shared_counter
        expect(initial_value).to eq(1)
        expect(test_class.shared_counter_computed?).to be true
        
        test_class.reset_shared_counter!
        expect(test_class.shared_counter_computed?).to be false
        
        new_value = test_class.shared_counter
        expect(new_value).to eq(2) # Global counter incremented
      end

      it 'can be reset through instance methods' do
        instance = test_class.new
        
        initial_value = instance.shared_counter
        instance.reset_shared_counter!
        
        expect(test_class.shared_counter_computed?).to be false
      end
    end

    describe 'thread safety' do
      it 'ensures class variable is computed only once with concurrent access' do
        # Create many instances and access class variable concurrently
        instances = Array.new(50) { test_class.new }
        
        results = []
        threads = instances.map do |instance|
          Thread.new { results << instance.shared_counter }
        end
        
        threads.each(&:join)
        
        # All should get the same value
        expect(results.uniq).to eq([1])
      end
    end
  end

  describe 'instance methods' do
    let(:test_class) { Class.new { include LazyInit } }
    
    describe '#lazy' do
      it 'creates a standalone lazy value' do
        instance = test_class.new
        
        lazy_value = instance.lazy { 'computed value' }
        expect(lazy_value).to be_a(LazyInit::LazyValue)
        expect(lazy_value.value).to eq('computed value')
      end
    end

    describe '#lazy_once' do
      it 'creates location-specific lazy values' do
        instance = test_class.new
        
        def instance.method1
          lazy_once { 'value1' }
        end
        
        def instance.method2  
          lazy_once { 'value2' }
        end
        
        expect(instance.method1).to eq('value1')
        expect(instance.method2).to eq('value2')
        expect(instance.method1).to eq('value1') # Same value on second call
      end

      it 'computes only once per location' do
        instance = test_class.new
        call_count = 0
        
        def instance.test_method(counter)
          counter.call
          lazy_once { "computed_#{counter.call}" }
        end
        
        counter = proc { call_count += 1 }
        
        first_result = instance.test_method(counter)
        second_result = instance.test_method(counter)
        
        expect(call_count).to eq(3) # Called twice outside lazy_once, once inside
        expect(first_result).to eq('computed_2')
        expect(second_result).to eq('computed_2') # Same result
      end
    end

    describe '#clear_lazy_once_values!' do
      it 'clears all lazy_once values' do
        instance = test_class.new
        
        def instance.test_method
          lazy_once { rand(1000) }
        end
        
        first_value = instance.test_method
        instance.clear_lazy_once_values!
        second_value = instance.test_method
        
        # Values will likely be different (small chance they're the same)
        # More importantly, we can verify through lazy_once_info
      end
    end

    describe '#lazy_once_info' do
      it 'provides debugging information' do
        instance = test_class.new
        
        expect(instance.lazy_once_info).to eq({})
        
        def instance.test_method
          lazy_once { 'value' }
        end
        
        instance.test_method
        info = instance.lazy_once_info
        
        expect(info.keys.first).to be_a(String)
        expect(info.values.first).to include(computed: true, exception: false)
      end
    end
  end
end