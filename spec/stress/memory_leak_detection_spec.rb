# frozen_string_literal: true

require_relative './stress_helper'

RSpec.describe 'Memory Leak Detection Tests', :stress do
  # Memory measurement utilities
  def measure_memory_usage
    GC.start
    GC.compact if GC.respond_to?(:compact)

    case RUBY_PLATFORM
    when /linux/
      `cat /proc/#{Process.pid}/status | grep VmRSS`.split[1].to_i / 1024
    when /darwin/
      `ps -o rss= -p #{Process.pid}`.to_i / 1024
    else
      GC.stat[:heap_allocated_pages] * 4096 / 1024 / 1024 # Rough estimate
    end
  rescue StandardError
    GC.stat[:heap_allocated_pages] * 4096 / 1024 / 1024
  end

  def force_gc_and_measure
    3.times do
      GC.start
      GC.compact if GC.respond_to?(:compact)
    end
    sleep 0.01 # Allow GC to complete
    measure_memory_usage
  end

  def detect_memory_leak(iterations: 1000, threshold_mb: 50, &block)
    initial_memory = force_gc_and_measure

    iterations.times(&block)

    final_memory = force_gc_and_measure
    growth = final_memory - initial_memory

    {
      initial: initial_memory,
      final: final_memory,
      growth: growth,
      leak_detected: growth > threshold_mb,
      growth_per_iteration: growth.to_f / iterations * 1000 # MB per 1000 iterations
    }
  end

  describe 'DependencyResolver cache memory leaks' do
    it 'detects cache accumulation with many short-lived instances' do
      # MOST CRITICAL TEST - this cache can grow indefinitely
      test_class = Class.new do
        extend LazyInit

        lazy_attr_reader :config do
          { id: rand(1_000_000) }
        end

        lazy_attr_reader :service, depends_on: [:config] do
          "service_#{config[:id]}"
        end
      end

      puts "\n=== DependencyResolver Cache Leak Test ==="

      result = detect_memory_leak(iterations: 2000, threshold_mb: 30) do |i|
        # Create many instances to stress the instance_resolution_cache
        instance = test_class.new
        instance.service # Trigger dependency resolution

        # Occasionally check cache size
        if i % 500 == 0
          resolver = test_class.dependency_resolver
          cache = resolver.instance_variable_get(:@instance_resolution_cache)
          puts "  Iteration #{i}: Cache size: #{cache.size}" if cache
        end
      end

      puts "Memory growth: #{result[:growth]}MB over 2000 iterations"
      puts "Growth per 1K iterations: #{result[:growth_per_iteration].round(2)}MB"

      # Check final cache size - this is the smoking gun
      resolver = test_class.dependency_resolver
      final_cache = resolver.instance_variable_get(:@instance_resolution_cache)
      puts "Final cache size: #{final_cache&.size || 0} entries"

      # LEAK DETECTION: Cache should not grow beyond reasonable bounds
      expect(final_cache&.size || 0).to be < 1500,
                                        "DependencyResolver cache grew to #{final_cache&.size} entries - potential memory leak!"

      # MEMORY GROWTH: Should not exceed threshold
      if result[:leak_detected]
        puts '⚠️  POTENTIAL MEMORY LEAK DETECTED in DependencyResolver cache'
        puts "   Growth: #{result[:growth]}MB suggests cache accumulation"
      end

      expect(result[:growth]).to be < 30,
                                 "Memory grew by #{result[:growth]}MB - DependencyResolver cache leak suspected"
    end

    it 'verifies cache cleanup behavior under extreme load' do
      test_class = Class.new do
        extend LazyInit
        lazy_attr_reader :data, depends_on: [] do
          Array.new(1000) { rand.to_s } # Moderately large object
        end
      end

      resolver = test_class.dependency_resolver

      # Stress test the cache with rapid instance creation/destruction
      5000.times do |i|
        instance = test_class.new
        instance.data

        # Check cache size periodically
        next unless i % 1000 == 0

        cache = resolver.instance_variable_get(:@instance_resolution_cache)
        cache_size = cache&.size || 0
        puts "Cache size at #{i}: #{cache_size}"

        # Cache should be cleaned up and not grow indefinitely
        expect(cache_size).to be < 2000,
                              "Cache size #{cache_size} too large at iteration #{i}"
      end
    end
  end

  describe 'lazy_once cache memory leaks' do
    it 'detects cache accumulation with diverse call locations' do
      test_class = Class.new { include LazyInit }

      puts "\n=== Lazy_once Cache Leak Test ==="

      result = detect_memory_leak(iterations: 1000, threshold_mb: 40) do |i|
        instance = test_class.new

        # Simulate many different call locations by using eval
        # This creates new caller locations for each iteration
        eval <<-RUBY, binding, __FILE__, __LINE__ + 1
          instance.define_singleton_method("method_#{i}") do
            lazy_once(max_entries: 200) do
              Array.new(500) { "data_\#{rand(1000)}" }
            end
          end
          instance.send("method_#{i}")
        RUBY

        # Check cache size periodically
        if i % 200 == 0
          cache = instance.instance_variable_get(:@lazy_once_cache)
          puts "  Iteration #{i}: Instance cache size: #{cache&.size || 0}"
        end
      end

      puts "Memory growth: #{result[:growth]}MB"

      # Memory should not grow excessively due to cache accumulation
      puts '⚠️  POTENTIAL MEMORY LEAK in lazy_once cache' if result[:leak_detected]

      expect(result[:growth]).to be < 40,
                                 "Memory grew by #{result[:growth]}MB - lazy_once cache leak suspected"
    end

    it 'verifies TTL cleanup effectiveness over time' do
      test_class = Class.new { include LazyInit }
      instance = test_class.new

      # Create many cached entries with short TTL
      100.times do |i|
        instance.define_singleton_method("ttl_method_#{i}") do
          lazy_once(ttl: 0.1, max_entries: 50) do
            Array.new(1000) { "ttl_data_#{rand(10_000)}" }
          end
        end
        instance.send("ttl_method_#{i}")
      end

      initial_cache_size = instance.instance_variable_get(:@lazy_once_cache)&.size || 0
      puts "Initial cache size: #{initial_cache_size}"

      # Wait for TTL expiration
      sleep(0.2)

      # Trigger cleanup by creating new entry
      instance.define_singleton_method(:cleanup_trigger) do
        lazy_once(ttl: 0.1) { 'trigger_cleanup' }
      end
      instance.cleanup_trigger

      final_cache_size = instance.instance_variable_get(:@lazy_once_cache)&.size || 0
      puts "Final cache size after TTL: #{final_cache_size}"

      # TTL should have cleaned up most entries
      expect(final_cache_size).to be < (initial_cache_size * 0.5),
                                  "TTL cleanup ineffective: #{initial_cache_size} → #{final_cache_size}"
    end
  end

  describe 'class-level lazy value memory leaks' do
    it 'detects accumulation of class-level lazy values' do
      puts "\n=== Class-level Lazy Value Leak Test ==="

      initial_memory = force_gc_and_measure
      class_count = 0

      # Create many classes with class-level lazy values holding large objects
      100.times do |i|
        class_name = "TestClass#{i}"

        test_class = Class.new do
          extend LazyInit

          lazy_class_variable :large_shared_resource do
            # Large object that should be shared but might leak
            {
              id: rand(1_000_000),
              data: Array.new(10_000) { "shared_data_#{rand(1000)}" },
              timestamp: Time.now.to_f
            }
          end

          lazy_class_variable :another_resource do
            Array.new(5000) { "more_data_#{rand(1000)}" }
          end
        end

        # Trigger lazy loading
        test_class.large_shared_resource
        test_class.another_resource

        class_count += 1

        next unless i % 20 == 0

        current_memory = force_gc_and_measure
        growth = current_memory - initial_memory
        puts "  Created #{class_count} classes, memory: #{current_memory}MB (+#{growth}MB)"
      end

      final_memory = force_gc_and_measure
      total_growth = final_memory - initial_memory

      puts "Total memory growth: #{total_growth}MB for #{class_count} classes"
      puts "Memory per class: #{(total_growth.to_f / class_count).round(2)}MB"

      # Each class should not consume excessive memory
      memory_per_class = total_growth.to_f / class_count
      expect(memory_per_class).to be < 5,
                                  "Each class consumes #{memory_per_class}MB - potential class-level leak"
    end

    it 'verifies class variable cleanup after reset' do
      test_class = Class.new do
        extend LazyInit

        lazy_class_variable :resettable_resource do
          Array.new(20_000) { "large_data_#{rand(1000)}" }
        end
      end

      # Initialize the resource
      initial_resource = test_class.resettable_resource
      initial_memory = force_gc_and_measure

      # Reset should clear the class variable
      test_class.reset_resettable_resource!

      # Force GC to potentially clean up the old resource
      memory_after_reset = force_gc_and_measure

      # Re-initialize with new resource
      new_resource = test_class.resettable_resource
      final_memory = force_gc_and_measure

      puts "Memory: Initial #{initial_memory}MB, After reset: #{memory_after_reset}MB, Final: #{final_memory}MB"

      # Resources should be different instances
      expect(new_resource.object_id).not_to eq(initial_resource.object_id)

      # Memory should not accumulate excessively after reset
      memory_growth = final_memory - initial_memory
      expect(memory_growth).to be < 20,
                               "Memory grew by #{memory_growth}MB after reset - potential leak in class variables"
    end
  end

  describe 'thread-local variable memory leaks' do
    it 'detects thread-local variable accumulation' do
      test_class = Class.new do
        extend LazyInit

        lazy_attr_reader :config do
          { setting: 'value' }
        end

        lazy_attr_reader :complex_service, depends_on: [:config] do
          "service_using_#{config[:setting]}"
        end
      end

      puts "\n=== Thread-local Variable Leak Test ==="

      initial_memory = force_gc_and_measure
      thread_count = 0

      # Create many threads to stress thread-local variables
      50.times do |batch|
        threads = 20.times.map do |_i|
          Thread.new do
            instance = test_class.new
            # This should set thread-local variables during dependency resolution
            instance.complex_service

            # Verify thread-local variables are set
            resolution_stack = Thread.current[:lazy_init_resolution_stack]
            cache_resolving = Thread.current[:lazy_init_cache_resolving]

            # Thread locals should be cleaned up after resolution
            expect(resolution_stack).to be_nil_or_empty
            expect(cache_resolving).to be_falsy
          end
        end

        threads.each(&:join)
        thread_count += 20

        next unless batch % 10 == 0

        current_memory = force_gc_and_measure
        growth = current_memory - initial_memory
        puts "  Processed #{thread_count} threads, memory: #{current_memory}MB (+#{growth}MB)"
      end

      final_memory = force_gc_and_measure
      total_growth = final_memory - initial_memory

      puts "Total memory growth: #{total_growth}MB for #{thread_count} threads"

      # Thread-local variables should not cause significant memory growth
      expect(total_growth).to be < 30,
                              "Memory grew by #{total_growth}MB - potential thread-local variable leak"
    end
  end

  describe 'circular reference memory leaks' do
    it 'detects circular references in lazy value chains' do
      # Create objects that might reference each other circularly
      test_class = Class.new do
        extend LazyInit

        lazy_attr_reader :service_a do
          obj = Object.new
          instance_ref = self
          obj.define_singleton_method(:reference) { instance_ref.service_b }
          obj.define_singleton_method(:data) { Array.new(1000) { rand.to_s } }
          obj
        end

        lazy_attr_reader :service_b do
          obj = Object.new
          instance_ref = self
          obj.define_singleton_method(:reference) { instance_ref.service_a }
          obj.define_singleton_method(:data) { Array.new(1000) { rand.to_s } }
          obj
        end
      end

      puts "\n=== Circular Reference Leak Test ==="

      result = detect_memory_leak(iterations: 500, threshold_mb: 30) do |i|
        instance = test_class.new

        # Access both services to create potential circular references
        service_a = instance.service_a
        service_b = instance.service_b

        # Verify circular references exist
        expect(service_a.reference).to be(service_b)
        expect(service_b.reference).to be(service_a)

        # Clear references to allow GC (if no leak)
        instance = nil
        service_a = nil
        service_b = nil

        # Force GC periodically
        GC.start if i % 100 == 0
      end

      puts "Memory growth: #{result[:growth]}MB"

      puts '⚠️  POTENTIAL CIRCULAR REFERENCE LEAK detected' if result[:leak_detected]

      expect(result[:growth]).to be < 30,
                                 "Memory grew by #{result[:growth]}MB - circular reference leak suspected"
    end
  end

  describe 'long-term stability under realistic usage' do
    it 'simulates production-like usage patterns' do
      # Simulate a realistic Rails-like application
      app_class = Class.new do
        extend LazyInit

        lazy_attr_reader :config do
          { database_url: "postgresql://localhost/test_#{rand(1000)}" }
        end

        lazy_attr_reader :database, depends_on: [:config] do
          "Database connection to #{config[:database_url]}"
        end

        lazy_class_variable :shared_cache do
          Array.new(5000) { "shared_#{rand(10_000)}" }
        end
      end

      worker_class = Class.new do
        include LazyInit

        def process_job(job_id)
          lazy_once(ttl: 300, max_entries: 100) do
            Array.new(2000) { "job_data_#{job_id}_#{rand(1000)}" }
          end
        end
      end

      puts "\n=== Production Simulation Leak Test ==="

      initial_memory = force_gc_and_measure

      # Simulate 30 minutes of production traffic
      iterations = 3000
      iterations.times do |i|
        # Simulate request processing
        app = app_class.new
        app.database # Trigger dependency chain

        # Simulate background job processing
        worker = worker_class.new
        worker.process_job(i % 50) # Limited job variety

        # Simulate periodic cleanup
        if i % 500 == 0
          current_memory = force_gc_and_measure
          growth = current_memory - initial_memory
          puts "  #{i} iterations: #{current_memory}MB (+#{growth}MB)"

          # Memory should stabilize, not grow linearly
          if i > 1000
            growth_rate = growth.to_f / i * 1000
            expect(growth_rate).to be < 10,
                                   "Linear memory growth detected: #{growth_rate}MB/1000 iterations"
          end
        end

        # Clear references
        app = nil
        worker = nil
      end

      final_memory = force_gc_and_measure
      total_growth = final_memory - initial_memory

      puts "Final memory growth: #{total_growth}MB after #{iterations} iterations"
      puts "Growth rate: #{(total_growth.to_f / iterations * 1000).round(3)}MB per 1000 operations"

      # Long-term memory growth should be minimal
      expect(total_growth).to be < 100,
                              "Excessive long-term memory growth: #{total_growth}MB"
    end
  end

  describe 'exception state memory leaks' do
    it 'detects memory accumulation from cached exceptions with large contexts' do
      puts "\n=== Exception State Memory Leak Test ==="

      test_class = Class.new do
        extend LazyInit

        lazy_attr_reader :failing_service do
          # Create large context before failing
          large_context = Array.new(10_000) { "context_data_#{rand(1000)}" }
          deep_stack = []

          # Create deep call stack to increase backtrace size
          10.times do |_i|
            deep_stack << lambda do |level|
              raise StandardError, "Service failed with context: #{large_context.first(10).join(',')}" unless level > 0

              deep_stack[level - 1].call(level - 1)

              # Fail with large context potentially captured in exception
            end
          end

          deep_stack.last.call(9)
        end
      end

      result = detect_memory_leak(iterations: 200, threshold_mb: 25) do |i|
        instance = test_class.new

        # Trigger exception multiple times - should be cached
        begin
          instance.failing_service
        rescue StandardError
          # Exception should be cached, not recreated
        end

        begin
          instance.failing_service # Should use cached exception
        rescue StandardError
        end

        # Check exception caching state
        if i % 50 == 0
          lazy_value = instance.instance_variable_get(:@failing_service_lazy_value)
          if lazy_value
            cached_exception = lazy_value.exception
            puts "  Iteration #{i}: Exception cached: #{!cached_exception.nil?}"
            if cached_exception
              backtrace_size = cached_exception.backtrace&.size || 0
              puts "    Backtrace size: #{backtrace_size} frames"
            end
          end
        end
      end

      puts "Memory growth from cached exceptions: #{result[:growth]}MB"

      if result[:leak_detected]
        puts '⚠️  POTENTIAL EXCEPTION MEMORY LEAK detected'
        puts '   Large exceptions with deep backtraces may be accumulating'
      end

      expect(result[:growth]).to be < 25,
                                 "Memory grew by #{result[:growth]}MB - exception state leak suspected"
    end

    it 'verifies exception cleanup after reset' do
      test_class = Class.new do
        extend LazyInit

        lazy_attr_reader :expensive_failure do
          # Create expensive context that might be captured
          expensive_data = Array.new(5000) { "expensive_#{rand(10_000)}" }
          raise StandardError, "Failed with #{expensive_data.size} items"
        end
      end

      instance = test_class.new

      # Trigger exception
      begin
        instance.expensive_failure
      rescue StandardError
      end

      # Verify exception is cached
      expect(instance.expensive_failure_computed?).to be false
      lazy_value = instance.instance_variable_get(:@expensive_failure_lazy_value)
      expect(lazy_value).not_to be_nil
      expect(lazy_value.exception?).to be true

      initial_memory = force_gc_and_measure

      # Reset should clear exception state
      instance.reset_expensive_failure!

      memory_after_reset = force_gc_and_measure
      growth = memory_after_reset - initial_memory

      puts "Memory change after exception reset: #{growth}MB"

      # Exception state should be cleared after reset
      expect(instance.expensive_failure_computed?).to be false

      # After reset, lazy_value should be cleared or have no exception
      new_lazy_value = instance.instance_variable_get(:@expensive_failure_lazy_value)
      expect(new_lazy_value.exception?).to be false if new_lazy_value

      # Memory should not grow significantly (some variance is normal)
      expect(growth.abs).to be < 5,
                            "Exception reset caused #{growth}MB memory change - potential cleanup issue"
    end
  end

  describe 'mutex proliferation memory leaks' do
    it 'detects memory accumulation from excessive mutex creation' do
      puts "\n=== Mutex Proliferation Leak Test ==="

      initial_memory = force_gc_and_measure
      created_classes = []

      # Create many classes that each should get their own mutexes
      500.times do |i|
        test_class = Class.new do
          extend LazyInit

          lazy_attr_reader :simple_value do
            "value_#{i}"
          end

          # Class should get @lazy_init_class_mutex and @lazy_init_simple_mutex
        end

        # Trigger mutex creation by accessing lazy attribute
        instance = test_class.new
        instance.simple_value

        created_classes << test_class

        next unless i % 100 == 0

        current_memory = force_gc_and_measure
        growth = current_memory - initial_memory
        puts "  Created #{i + 1} classes, memory: #{current_memory}MB (+#{growth}MB)"

        # Check mutex creation
        class_mutex = test_class.instance_variable_get(:@lazy_init_class_mutex)
        simple_mutex = test_class.instance_variable_get(:@lazy_init_simple_mutex)
        puts "    Class mutex: #{!class_mutex.nil?}, Simple mutex: #{!simple_mutex.nil?}"
      end

      final_memory = force_gc_and_measure
      total_growth = final_memory - initial_memory
      mutex_memory_per_class = total_growth.to_f / created_classes.size

      puts "Total mutex-related memory growth: #{total_growth}MB for #{created_classes.size} classes"
      puts "Memory per class (mutex overhead): #{mutex_memory_per_class.round(4)}MB"

      # Each class should not consume excessive memory for mutexes
      expect(mutex_memory_per_class).to be < 0.1,
                                        "Each class consumes #{mutex_memory_per_class}MB for mutexes - potential proliferation issue"

      # Total growth should be reasonable
      expect(total_growth).to be < 50,
                              "Total mutex memory grew by #{total_growth}MB - mutex proliferation suspected"
    end
  end

  describe 'closure capture memory leaks' do
    it 'detects memory leaks from large objects captured in lazy block closures' do
      puts "\n=== Closure Capture Memory Leak Test ==="

      result = detect_memory_leak(iterations: 100, threshold_mb: 30) do |i|
        # Create large local variables that might be captured by lazy blocks
        large_array = Array.new(5000) { "large_data_#{rand(10_000)}" }
        large_hash = Hash[(0...2000).map { |j| [j, "hash_value_#{j}_#{rand(1000)}"] }]
        large_string = 'x' * 50_000

        test_class = Class.new do
          extend LazyInit

          # This lazy block might capture the large local variables
          lazy_attr_reader :service do
            # Access variables to ensure they're captured in closure
            result = {
              array_size: large_array.size,
              hash_size: large_hash.size,
              string_length: large_string.length
            }
            "Service with context: #{result}"
          end
        end

        instance = test_class.new
        value = instance.service

        # Verify the service actually uses the captured variables
        expect(value).to include('array_size')
        expect(value).to include('5000')
        expect(value).to include('hash_size')
        expect(value).to include('2000')
        expect(value).to include('string_length')
        expect(value).to include('50000')

        puts "  Iteration #{i}: Created instance with large closure context" if i % 25 == 0

        # Clear local references - closure should still hold them
        large_array = nil
        large_hash = nil
        large_string = nil
        instance = nil
        value = nil
      end

      puts "Memory growth from closure captures: #{result[:growth]}MB"

      if result[:leak_detected]
        puts '⚠️  POTENTIAL CLOSURE CAPTURE LEAK detected'
        puts '   Large objects captured in lazy block closures may be accumulating'
      end

      expect(result[:growth]).to be < 30,
                                 "Memory grew by #{result[:growth]}MB - closure capture leak suspected"
    end

    it 'verifies closure memory is released after instance cleanup' do
      large_captured_data = Array.new(10_000) { "captured_#{rand(1000)}" }

      test_class = Class.new do
        extend LazyInit

        lazy_attr_reader :service_with_capture do
          # Capture the large data in closure
          "Service using #{large_captured_data.first(5).join(',')}"
        end
      end

      initial_memory = force_gc_and_measure

      # Create instance and trigger lazy loading
      instance = test_class.new
      result = instance.service_with_capture
      expect(result).to include('captured_')

      memory_with_instance = force_gc_and_measure

      # Clear instance and captured data references
      instance = nil
      large_captured_data = nil

      memory_after_cleanup = force_gc_and_measure

      growth_with_instance = memory_with_instance - initial_memory
      growth_after_cleanup = memory_after_cleanup - initial_memory

      puts "Memory: +#{growth_with_instance}MB with instance, +#{growth_after_cleanup}MB after cleanup"

      # Memory should be mostly released after cleanup
      memory_released = growth_with_instance - growth_after_cleanup
      release_percentage = memory_released / growth_with_instance.to_f * 100 if growth_with_instance > 0

      puts "Memory released: #{memory_released}MB (#{release_percentage&.round(1)}%)"

      # Most memory should be released (allowing some variance for GC timing)
      if growth_with_instance > 1  # Only check if there was significant growth
        expect(release_percentage).to be > 50,
                                      "Only #{release_percentage&.round(1)}% of memory released - closure capture leak suspected"
      end
    end
  end

  private

  def be_nil_or_empty
    satisfy { |value| value.nil? || (value.respond_to?(:empty?) && value.empty?) }
  end
end
