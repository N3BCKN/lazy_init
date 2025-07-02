require_relative './stress_helper'

RSpec.describe 'Memory Leak Detection Tests', :stress do
  # Helper to measure memory in MB with better accuracy
  def current_memory_mb
    case RUBY_PLATFORM
    when /linux/
      # Use VmRSS for accurate RSS measurement
      rss = `grep VmRSS /proc/#{Process.pid}/status`.split[1].to_i
      rss / 1024.0
    when /darwin/
      # Use ps for macOS
      rss = `ps -o rss= -p #{Process.pid}`.to_i
      rss / 1024.0
    else
      # Fallback - use GC stats (less accurate but portable)
      GC.stat[:heap_allocated_pages] * 4096 / 1024.0 / 1024.0
    end
  rescue StandardError
    0
  end

  # Helper to get object counts by class
  def object_count(klass)
    ObjectSpace.each_object(klass).count
  end

  # Helper to force comprehensive GC
  def aggressive_gc
    5.times do
      GC.start(full_mark: true, immediate_sweep: true)
      GC.compact if GC.respond_to?(:compact)
    end
    sleep 0.01 # Allow time for finalization
  end

  # Helper to create WeakRef for tracking object lifecycle
  def create_tracked_object
    obj = Object.new
    weak_ref = defined?(WeakRef) ? WeakRef.new(obj) : nil
    [obj, weak_ref]
  end

  describe 'closure reference retention' do
    it 'releases closure references after computation to prevent memory leaks' do
      initial_memory = current_memory_mb
      
      # Create lazy values that capture large objects in closures
      lazy_values = 50.times.map do |i|
        # Each large object is ~10MB of strings
        large_object = Array.new(100_000) { "data_#{i}_#{rand(1000)}_#{'x' * 100}" }
        
        LazyInit::LazyValue.new do
          large_object.first # Access to create closure capture
        end
      end

      # Compute all values (closures should be executed)
      lazy_values.each(&:value)

      # Clear our direct references to lazy values
      lazy_values.clear
      lazy_values = nil

      # Force aggressive garbage collection
      aggressive_gc

      final_memory = current_memory_mb
      memory_growth = final_memory - initial_memory
      
      puts "Closure retention test results:"
      puts "  Initial memory: #{initial_memory.round(2)} MB"
      puts "  Final memory: #{final_memory.round(2)} MB"
      puts "  Memory growth: #{memory_growth.round(2)} MB"
      puts "  Expected: < 100 MB if closures are properly released"
      puts "  Expected: > 400 MB if closures are retained"
      
      # If LazyValue retains closure references, we'd see ~500MB growth
      # If properly released, should be < 100MB
      expect(memory_growth).to be < 200, 
        "Memory grew by #{memory_growth.round(2)} MB - LazyValue likely retaining closure references!"
    end

    it 'does not accumulate closure references in repeated computations' do
      initial_memory = current_memory_mb
      
      # Create many lazy values with large closures
      100.times do |batch|
        lazy_values = []
        
        50.times do |i|
          # Each closure captures a large object
          large_data = Array.new(10_000) { "batch_#{batch}_item_#{i}" }
          
          lazy_value = LazyInit::LazyValue.new do
            large_data.sum(&:length) # Force closure capture
          end
          
          lazy_values << lazy_value
        end
        
        # Compute all values
        lazy_values.each(&:value)
        
        # Clear references
        lazy_values.clear
        
        # Periodic GC
        aggressive_gc if batch % 10 == 0
      end
      
      final_memory = current_memory_mb
      memory_growth = final_memory - initial_memory
      
      puts "Closure accumulation test:"
      puts "  Initial memory: #{initial_memory.round(2)} MB"
      puts "  Final memory: #{final_memory.round(2)} MB"
      puts "  Growth: #{memory_growth.round(2)} MB"
      
      # Should not accumulate significant memory
      expect(memory_growth).to be < 50, 
        "Memory grew by #{memory_growth.round(2)} MB - possible closure accumulation"
    end
  end

  describe 'class redefinition memory leaks' do
    it 'does not retain references to old class definitions' do
      initial_memory = current_memory_mb
      initial_classes = object_count(Class)
      
      module_names = []
      
      # Simulate Rails code reloading
      100.times do |i|
        module_name = "TestModule#{i}_#{rand(10000)}"
        module_names << module_name
        
        # Create a module with lazy attributes (simulates Rails class reloading)
        test_module = Module.new do
          extend LazyInit
          
          lazy_attr_reader :expensive_resource do
            Array.new(1000) { "resource_#{rand(1000)}" }
          end
          
          lazy_attr_reader :another_resource do
            Hash.new { |h, k| h[k] = Array.new(100) { rand.to_s } }
          end
        end
        
        # Assign to constant (simulates Rails constant loading)
        Object.const_set(module_name, test_module)
        
        # Use the lazy attributes (create LazyValue instances)
        instance = Object.new.extend(test_module)
        instance.expensive_resource
        instance.another_resource
        
        # Simulate constant removal (Rails unloading)
        Object.send(:remove_const, module_name)
        
        # Clear local references
        test_module = nil
        instance = nil
        
        # Periodic cleanup
        if i % 10 == 0
          aggressive_gc
          
          current_memory = current_memory_mb
          current_classes = object_count(Class)
          
          puts "Iteration #{i}: Memory: #{current_memory.round(2)} MB, Classes: #{current_classes}"
        end
      end
      
      # Final cleanup
      aggressive_gc
      
      final_memory = current_memory_mb
      final_classes = object_count(Class)
      
      memory_growth = final_memory - initial_memory
      class_growth = final_classes - initial_classes
      
      puts "Class redefinition leak test:"
      puts "  Initial memory: #{initial_memory.round(2)} MB"
      puts "  Final memory: #{final_memory.round(2)} MB"
      puts "  Memory growth: #{memory_growth.round(2)} MB"
      puts "  Initial classes: #{initial_classes}"
      puts "  Final classes: #{final_classes}"
      puts "  Class growth: #{class_growth}"
      
      # Memory growth should be reasonable
      expect(memory_growth).to be < 100, 
        "Memory grew by #{memory_growth.round(2)} MB during class redefinition"
      
      # Class count should not grow significantly
      expect(class_growth).to be < 50,
        "Class count grew by #{class_growth} - possible class retention"
    end
  end

  describe 'dependency resolver memory leaks' do
    it 'does not accumulate dependency graph references' do
      initial_memory = current_memory_mb
      
      resolvers = []
      
      # Create many dependency resolvers with complex graphs
      50.times do |batch|
        test_class = Class.new do
          extend LazyInit
          
          # Create complex dependency chains
          lazy_attr_reader :base_config do
            { setting: "value_#{batch}" }
          end
          
          lazy_attr_reader :derived_config, depends_on: [:base_config] do
            base_config.merge(derived: "derived_#{batch}")
          end
          
          lazy_attr_reader :service_a, depends_on: [:base_config, :derived_config] do
            "service_a_#{base_config[:setting]}_#{derived_config[:derived]}"
          end
          
          lazy_attr_reader :service_b, depends_on: [:derived_config] do
            "service_b_#{derived_config[:derived]}"
          end
          
          lazy_attr_reader :final_service, depends_on: [:service_a, :service_b] do
            "final_#{service_a}_#{service_b}"
          end
        end
        
        # Access dependency resolver and trigger resolution
        resolver = test_class.dependency_resolver
        resolvers << resolver
        
        # Create instances and trigger dependency resolution
        5.times do
          instance = test_class.new
          instance.final_service # This triggers full dependency chain
        end
        
        # Clear class reference
        test_class = nil
        
        # Periodic cleanup
        if batch % 10 == 0
          aggressive_gc
          current_memory = current_memory_mb
          puts "Batch #{batch}: Memory: #{current_memory.round(2)} MB"
        end
      end
      
      # Clear resolver references
      resolvers.clear
      
      aggressive_gc
      
      final_memory = current_memory_mb
      memory_growth = final_memory - initial_memory
      
      puts "Dependency resolver leak test:"
      puts "  Initial memory: #{initial_memory.round(2)} MB"
      puts "  Final memory: #{final_memory.round(2)} MB"
      puts "  Memory growth: #{memory_growth.round(2)} MB"
      
      expect(memory_growth).to be < 50,
        "Memory grew by #{memory_growth.round(2)} MB - possible dependency graph retention"
    end
  end

  describe 'lazy_once cache memory leaks' do
    it 'properly manages cache memory with TTL expiration' do
      test_class = Class.new { include LazyInit }
      instance = test_class.new
      
      initial_memory = current_memory_mb
      
      # Generate many cache entries that should expire
      200.times do |i|
        instance.define_singleton_method("method_#{i}") do
          lazy_once(ttl: 0.01, max_entries: 50) do
            Array.new(1000) { "cached_data_#{i}_#{rand(1000)}" }
          end
        end
        
        # Access the method to create cache entry
        instance.send("method_#{i}")
        
        # Let some entries expire
        sleep(0.02) if i % 50 == 0
      end
      
      # Force cache cleanup by accessing new methods
      10.times do |i|
        instance.define_singleton_method("cleanup_method_#{i}") do
          lazy_once(ttl: 0.01, max_entries: 50) { "cleanup" }
        end
        instance.send("cleanup_method_#{i}")
      end
      
      aggressive_gc
      
      final_memory = current_memory_mb
      memory_growth = final_memory - initial_memory
      
      cache_stats = instance.lazy_once_statistics
      
      puts "Lazy_once cache leak test:"
      puts "  Initial memory: #{initial_memory.round(2)} MB"
      puts "  Final memory: #{final_memory.round(2)} MB"
      puts "  Memory growth: #{memory_growth.round(2)} MB"
      puts "  Cache entries: #{cache_stats[:total_entries]}"
      puts "  Expected max entries: 50"
      
      # Cache should respect size limits
      expect(cache_stats[:total_entries]).to be <= 50,
        "Cache has #{cache_stats[:total_entries]} entries, expected <= 50"
      
      # Memory growth should be bounded
      expect(memory_growth).to be < 100,
        "Memory grew by #{memory_growth.round(2)} MB - possible cache memory leak"
    end

    it 'cleans up cache properly when instance is garbage collected' do
      initial_memory = current_memory_mb
      
      # Create instances with large cache entries
      10.times do |batch|
        instance = Class.new { include LazyInit }.new
        
        # Fill cache with large objects
        20.times do |i|
          instance.define_singleton_method("method_#{i}") do
            lazy_once do
              Array.new(10_000) { "batch_#{batch}_data_#{i}_#{'x' * 50}" }
            end
          end
          instance.send("method_#{i}")
        end
        
        # Don't keep reference to instance - let it be GC'd
      end
      
      # Force comprehensive GC
      aggressive_gc
      
      final_memory = current_memory_mb
      memory_growth = final_memory - initial_memory
      
      puts "Instance GC test:"
      puts "  Initial memory: #{initial_memory.round(2)} MB"
      puts "  Final memory: #{final_memory.round(2)} MB"
      puts "  Memory growth: #{memory_growth.round(2)} MB"
      puts "  Expected: < 50 MB if instances and caches are GC'd"
      
      expect(memory_growth).to be < 100,
        "Memory grew by #{memory_growth.round(2)} MB - instances/caches not being GC'd"
    end
  end

  describe 'long-running process simulation' do
    it 'maintains stable memory usage over extended operations' do
      initial_memory = current_memory_mb
      memory_samples = []
      
      # Simulate long-running Rails application
      duration = ENV['LEAK_TEST_DURATION']&.to_i || 30
      puts "\nRunning long-term memory leak test for #{duration} seconds..."
      
      start_time = Time.now
      iteration = 0
      
      while (Time.now - start_time) < duration
        # Simulate typical Rails request cycle
        service_class = Class.new do
          extend LazyInit
          
          lazy_attr_reader :database do
            Array.new(1000) { "db_connection_#{rand(1000)}" }
          end
          
          lazy_attr_reader :cache do
            Hash.new { |h, k| h[k] = "cached_#{k}_#{rand(1000)}" }
          end
          
          lazy_attr_reader :external_api do
            { client: "api_client", data: Array.new(500) { rand.to_s } }
          end
        end
        
        # Create instance and use lazy attributes (simulate request)
        instance = service_class.new
        instance.database
        instance.cache
        instance.external_api
        
        # Simulate some lazy_once usage
        if iteration % 100 == 0
          test_instance = Class.new { include LazyInit }.new
          
          5.times do |i|
            test_instance.define_singleton_method("temp_method_#{i}") do
              lazy_once(max_entries: 20) { Array.new(100) { rand.to_s } }
            end
            test_instance.send("temp_method_#{i}")
          end
        end
        
        # Sample memory every 5 seconds
        if iteration % 1000 == 0
          current_memory = current_memory_mb
          memory_samples << {
            time: Time.now - start_time,
            memory: current_memory,
            iteration: iteration
          }
          
          puts "  #{(Time.now - start_time).round(1)}s: #{current_memory.round(2)} MB (iteration #{iteration})"
          
          # Force GC periodically
          aggressive_gc if iteration % 5000 == 0
        end
        
        iteration += 1
        
        # Small delay to prevent CPU spinning
        sleep(0.001) if iteration % 1000 == 0
      end
      
      final_memory = current_memory_mb
      total_growth = final_memory - initial_memory
      
      puts "\nLong-running process results:"
      puts "  Duration: #{duration}s"
      puts "  Iterations: #{iteration}"
      puts "  Initial memory: #{initial_memory.round(2)} MB"
      puts "  Final memory: #{final_memory.round(2)} MB"
      puts "  Total growth: #{total_growth.round(2)} MB"
      puts "  Growth rate: #{(total_growth / duration * 3600).round(4)} MB/hour"
      
      # Analyze memory growth trend
      if memory_samples.size >= 3
        recent_samples = memory_samples.last(3)
        early_samples = memory_samples.first(3)
        
        recent_avg = recent_samples.sum { |s| s[:memory] } / recent_samples.size
        early_avg = early_samples.sum { |s| s[:memory] } / early_samples.size
        
        trend_growth = recent_avg - early_avg
        puts "  Trend analysis: #{trend_growth.round(2)} MB growth from start to end"
        
        # Memory growth should be bounded and not linear
        expect(total_growth).to be < 200, 
          "Excessive memory growth: #{total_growth.round(2)} MB over #{duration}s"
        
        # Growth rate should slow down over time (not linear leak)
        hourly_rate = total_growth / duration * 3600
        expect(hourly_rate).to be < 50,
          "High growth rate: #{hourly_rate.round(2)} MB/hour suggests memory leak"
      end
    end
  end

  describe 'mutex and thread resource cleanup' do
    it 'does not accumulate mutex objects or thread resources' do
      initial_memory = current_memory_mb
      initial_threads = Thread.list.size
      
      # Create many classes with lazy attributes (each gets mutexes)
      100.times do |i|
        test_class = Class.new do
          extend LazyInit
          
          lazy_attr_reader :resource_a do
            "resource_a_#{i}"
          end
          
          lazy_attr_reader :resource_b do
            "resource_b_#{i}"
          end
        end
        
        # Create instances and access attributes in threads
        threads = 5.times.map do
          Thread.new do
            instance = test_class.new
            instance.resource_a
            instance.resource_b
          end
        end
        
        threads.each(&:join)
        
        # Clear references
        test_class = nil
        threads = nil
        
        # Periodic cleanup
        if i % 20 == 0
          aggressive_gc
          current_threads = Thread.list.size
          puts "Iteration #{i}: Threads: #{current_threads}"
        end
      end
      
      aggressive_gc
      
      final_memory = current_memory_mb
      final_threads = Thread.list.size
      
      memory_growth = final_memory - initial_memory
      thread_growth = final_threads - initial_threads
      
      puts "Mutex and thread resource test:"
      puts "  Memory growth: #{memory_growth.round(2)} MB"
      puts "  Thread count growth: #{thread_growth}"
      
      expect(memory_growth).to be < 50,
        "Memory grew by #{memory_growth.round(2)} MB - possible mutex accumulation"
      
      expect(thread_growth).to be <= 2,
        "Thread count grew by #{thread_growth} - possible thread leak"
    end
  end
end