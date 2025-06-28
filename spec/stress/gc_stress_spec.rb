require_relative './stress_helper'

RSpec.describe 'GC Stress Tests', :stress do
  def with_gc_stress
    old_stress = GC.stress
    GC.stress = true
    yield
  ensure
    GC.stress = old_stress
  end

  def aggressive_gc_cycle
    3.times do
      GC.start
      GC.compact if GC.respond_to?(:compact)
    end
  end

  describe 'garbage collection stress scenarios' do
    it 'maintains correctness under GC stress' do
      test_class = Class.new do
        extend LazyInit

        lazy_attr_reader :object_data do
          # Create objects that will be subject to GC
          {
            strings: Array.new(100) { "string_#{rand(1000)}" },
            numbers: Array.new(100) { rand(1000) },
            nested: {
              deep: Array.new(50) { { value: rand.to_s } }
            }
          }
        end

        lazy_attr_reader :computation do
          (1..1000).map { |i| i * 2 }.sum
        end
      end

      instances = []
      results = []

      with_gc_stress do
        puts "\nRunning under GC stress..."

        # Create instances and trigger lazy loading under GC stress
        100.times do |i|
          instance = test_class.new
          instances << instance

          # Access lazy attributes
          object_data = instance.object_data
          computation = instance.computation

          results << {
            instance_id: i,
            object_data_size: object_data[:strings].size,
            computation_result: computation,
            computed_object: instance.object_data_computed?,
            computed_computation: instance.computation_computed?
          }

          # Force GC every 10 iterations
          aggressive_gc_cycle if i % 10 == 0
        end
      end

      puts "GC stress test completed with #{instances.size} instances"

      # Verify all results are consistent
      results.each_with_index do |result, i|
        expect(result[:object_data_size]).to eq(100)
        expect(result[:computation_result]).to eq(1_001_000) # Sum of (1..1000)*2
        expect(result[:computed_object]).to be true
        expect(result[:computed_computation]).to be true

        # Verify instances still work after GC stress
        instance = instances[i]
        expect(instance.object_data[:strings].size).to eq(100)
        expect(instance.computation).to eq(1_001_000)
      end
    end

    it 'handles concurrent access under GC stress' do
      test_class = Class.new do
        extend LazyInit

        lazy_attr_reader :shared_resource do
          # Create object that might be moved by GC.compact
          data = Array.new(1000) { |i| "shared_data_#{i}" }
          { id: rand(1_000_000), data: data, timestamp: Time.now.to_f }
        end
      end

      instance = test_class.new
      results = []
      errors = []
      mutex = Mutex.new

      with_gc_stress do
        puts "\nRunning concurrent access under GC stress..."

        # Multiple threads accessing the same lazy attribute under GC stress
        threads = 20.times.map do |thread_id|
          Thread.new do
            thread_results = []
            thread_errors = []

            100.times do |iteration|
              resource = instance.shared_resource

              thread_results << {
                thread: thread_id,
                iteration: iteration,
                resource_id: resource[:id],
                data_size: resource[:data].size,
                timestamp: resource[:timestamp]
              }

              # Trigger GC in some threads
              aggressive_gc_cycle if thread_id.even? && iteration % 20 == 0

            rescue StandardError => e
              thread_errors << {
                thread: thread_id,
                iteration: iteration,
                error: e.message,
                backtrace: e.backtrace.first(3)
              }
            end

            mutex.synchronize do
              results.concat(thread_results)
              errors.concat(thread_errors)
            end
          end
        end

        threads.each(&:join)
      end

      puts 'Concurrent GC stress test completed:'
      puts "  Total results: #{results.size}"
      puts "  Errors: #{errors.size}"

      expect(errors).to be_empty, "Unexpected errors: #{errors.first(3)}"

      # All threads should see the same resource (same object_id)
      unique_resource_ids = results.map { |r| r[:resource_id] }.uniq
      expect(unique_resource_ids.size).to eq(1), "Multiple resource IDs detected: #{unique_resource_ids}"

      # All should see the same data size and timestamp
      unique_data_sizes = results.map { |r| r[:data_size] }.uniq
      unique_timestamps = results.map { |r| r[:timestamp] }.uniq

      expect(unique_data_sizes).to eq([1000])
      expect(unique_timestamps.size).to eq(1)

      puts '  ✓ All threads saw consistent data'
      puts '  ✓ Thread safety maintained under GC stress'
    end

    it 'preserves lazy_once cache integrity under GC stress' do
      'GC stress tests only on CI or explicit request' unless ENV['RUN_STRESS_TESTS']

      test_class = Class.new do
        include LazyInit

        def cached_data(key)
          lazy_once(max_entries: 20, ttl: 60) do
            # Create objects that may be affected by GC
            Array.new(200) { "cached_#{key}_#{rand(1000)}" }
          end
        end
      end

      instance = test_class.new
      cache_results = {}

      with_gc_stress do
        puts "\nTesting lazy_once cache under GC stress..."

        # Fill cache with different keys
        20.times do |key|
          result = instance.cached_data(key)
          cache_results[key] = result.first # Store first element for comparison

          # Force GC after each cache entry
          aggressive_gc_cycle
        end

        # Verify cache integrity after GC stress
        20.times do |key|
          result = instance.cached_data(key)
          expect(result.first).to eq(cache_results[key]), "Cache corrupted for key #{key}"
          expect(result.size).to eq(200)
        end
      end

      # Check cache statistics
      stats = instance.lazy_once_statistics
      puts 'Cache statistics after GC stress:'
      puts "  Total entries: #{stats[:total_entries]}"
      puts "  Total accesses: #{stats[:total_accesses]}"

      expect(stats[:total_entries]).to eq(20)
      expect(stats[:total_accesses]).to eq(40) # 20 initial + 20 verification

      puts '  ✓ Cache integrity preserved under GC stress'
    end
  end
end
