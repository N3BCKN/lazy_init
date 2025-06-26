# frozen_string_literal: true

RSpec.describe 'Thread-Safe Dependency Injection' do
  describe 'concurrent dependency resolution' do
    let(:test_class) do
      Class.new do
        extend LazyInit
        
        lazy_attr_reader :config do
          sleep(0.001)  # Simulate potential race condition
          { database_url: 'postgresql://localhost/test', id: rand(1000000) }
        end
        
        lazy_attr_reader :database, depends_on: [:config] do
          sleep(0.001)
          "Connected to: #{config[:database_url]} (#{config[:id]})"
        end
        
        lazy_attr_reader :cache, depends_on: [:config] do
          sleep(0.001)
          "Cache for #{config[:id]}"
        end
        
        lazy_attr_reader :api_client, depends_on: [:config, :database, :cache] do
          sleep(0.001)
          "API client using #{database} and #{cache}"
        end
      end
    end

    it 'resolves complex dependencies without race conditions' do
      instance = test_class.new
      
      # Test with high concurrency
      results = []
      threads = 50.times.map do
        Thread.new do
          results << instance.api_client
        end
      end
      
      threads.each(&:join)
      
      # All threads should get the same result
      expect(results.uniq.size).to eq(1)
      
      # Verify all dependencies were computed
      expect(instance.config_computed?).to be true
      expect(instance.database_computed?).to be true
      expect(instance.cache_computed?).to be true
      expect(instance.api_client_computed?).to be true
    end

    it 'handles partial dependency access correctly' do
      instance = test_class.new
      
      # Multiple threads accessing different parts of dependency tree
      config_results = []
      database_results = []
      api_results = []
      
      threads = []
      
      # Threads accessing config directly
      10.times do
        threads << Thread.new { config_results << instance.config }
      end
      
      # Threads accessing database (depends on config)
      10.times do
        threads << Thread.new { database_results << instance.database }
      end
      
      # Threads accessing full dependency chain
      10.times do
        threads << Thread.new { api_results << instance.api_client }
      end
      
      threads.each(&:join)
      
      # All results within each category should be identical
      expect(config_results.uniq.size).to eq(1)
      expect(database_results.uniq.size).to eq(1)
      expect(api_results.uniq.size).to eq(1)
    end

    it 'maintains correct dependency order under concurrent access' do
      call_order = []
      call_mutex = Mutex.new
      
      ordered_class = Class.new do
        extend LazyInit
        
        lazy_attr_reader :step1 do
          call_mutex.synchronize { call_order << :step1 }
          sleep(0.002)
          'step1_result'
        end
        
        lazy_attr_reader :step2, depends_on: [:step1] do
          call_mutex.synchronize { call_order << :step2 }
          sleep(0.002)
          "step2_using_#{step1}"
        end
        
        lazy_attr_reader :step3, depends_on: [:step1] do
          call_mutex.synchronize { call_order << :step3 }
          sleep(0.002)
          "step3_using_#{step1}"
        end
        
        lazy_attr_reader :final, depends_on: [:step2, :step3] do
          call_mutex.synchronize { call_order << :final }
          sleep(0.002)
          "final: #{step2} + #{step3}"
        end
      end
      
      instance = ordered_class.new
      
      # Multiple threads all trying to access final result
      threads = 20.times.map do
        Thread.new { instance.final }
      end
      
      threads.each(&:join)
      
      # Check that dependencies were called in correct order
      expect(call_order.first).to eq(:step1)  # step1 must be first
      
      # step2 and step3 can be in any order, but both after step1
      step1_index = call_order.index(:step1)
      step2_index = call_order.index(:step2)
      step3_index = call_order.index(:step3)
      final_index = call_order.index(:final)
      
      expect(step2_index).to be > step1_index
      expect(step3_index).to be > step1_index
      expect(final_index).to be > step2_index
      expect(final_index).to be > step3_index
    end
  end

  describe 'circular dependency detection' do
    it 'properly detects circular dependencies in concurrent environment' do
      circular_class = Class.new do
        extend LazyInit
        
        lazy_attr_reader :a, depends_on: [:b] do
          'value_a'
        end
        
        lazy_attr_reader :b, depends_on: [:c] do
          'value_b'
        end
        
        lazy_attr_reader :c, depends_on: [:a] do
          'value_c'
        end
      end

      instance = circular_class.new
      
      # Multiple threads should all get the same circular dependency error
      exceptions = []
      threads = 10.times.map do
        Thread.new do
          begin
            instance.a
          rescue LazyInit::DependencyError => e
            exceptions << e.message
          end
        end
      end
      
      threads.each(&:join)
      
      # All threads should detect the same circular dependency
      expect(exceptions.size).to eq(10)
      expect(exceptions.uniq.size).to eq(1)
      expect(exceptions.first).to match(/Circular dependency detected/)
    end
  end

  describe 'performance under concurrent load' do
    it 'maintains reasonable performance with complex dependency graphs' do
      complex_class = Class.new do
        extend LazyInit
        
        # Create a diamond dependency pattern
        lazy_attr_reader :root do
          sleep(0.001)
          'root_value'
        end
        
        lazy_attr_reader :branch_a, depends_on: [:root] do
          sleep(0.001)
          "branch_a_#{root}"
        end
        
        lazy_attr_reader :branch_b, depends_on: [:root] do
          sleep(0.001)
          "branch_b_#{root}"
        end
        
        lazy_attr_reader :leaf, depends_on: [:branch_a, :branch_b] do
          sleep(0.001)
          "leaf_#{branch_a}_#{branch_b}"
        end
      end
      
      instance = complex_class.new
      
      start_time = Time.now
      
      # High concurrency test
      threads = 100.times.map do
        Thread.new { instance.leaf }
      end
      
      results = threads.map(&:value)
      end_time = Time.now
      
      duration = end_time - start_time
      
      # Should complete within reasonable time (< 1 second)
      expect(duration).to be < 1.0
      
      # All results should be identical
      expect(results.uniq.size).to eq(1)
      
      # All dependencies should be computed exactly once
      expect(instance.root_computed?).to be true
      expect(instance.branch_a_computed?).to be true
      expect(instance.branch_b_computed?).to be true
      expect(instance.leaf_computed?).to be true
    end
  end
end