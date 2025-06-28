# require_relative './stress_helper'

RSpec.describe 'Memory Pressure Tests', :stress do
  # Helper to get current memory usage (cross-platform)
  def current_memory_mb
    case RUBY_PLATFORM
    when /linux/
      `cat /proc/#{Process.pid}/status | grep VmRSS`.split[1].to_i / 1024
    when /darwin/
      `ps -o rss= -p #{Process.pid}`.to_i / 1024
    else
      0 # Fallback for unsupported platforms
    end
  rescue StandardError
    0
  end

  def force_gc_cycles(count = 3)
    count.times do
      GC.start
      GC.compact if GC.respond_to?(:compact)
    end
  end

  describe 'high memory usage scenarios' do
    it 'handles thousands of lazy attributes under memory pressure' do
      initial_memory = current_memory_mb

      # Create many classes with lazy attributes
      classes = 100.times.map do |i|
        Class.new do
          extend LazyInit

          # Multiple lazy attributes per class
          10.times do |j|
            lazy_attr_reader "attribute_#{j}".to_sym do
              # Create moderately large objects
              Array.new(1000) { "data_#{i}_#{j}_#{rand(1000)}" }
            end
          end
        end
      end

      # Create instances and trigger lazy loading
      instances = classes.map(&:new)

      # Measure memory before full initialization
      pre_init_memory = current_memory_mb

      # Initialize all lazy attributes
      instances.each do |instance|
        10.times do |j|
          instance.send("attribute_#{j}")
        end
      end

      post_init_memory = current_memory_mb
      memory_increase = post_init_memory - initial_memory

      puts "\nMemory Usage:"
      puts "  Initial: #{initial_memory} MB"
      puts "  Pre-init: #{pre_init_memory} MB"
      puts "  Post-init: #{post_init_memory} MB"
      puts "  Increase: #{memory_increase} MB"

      # Memory increase should be reasonable (not exponential)
      expect(memory_increase).to be < 500 # Less than 500MB for this test

      # All attributes should still be computed correctly
      instances.each do |instance|
        10.times do |j|
          expect(instance.send("attribute_#{j}_computed?")).to be true
          expect(instance.send("attribute_#{j}")).to be_an(Array)
        end
      end

      # Force GC and verify no major leaks
      force_gc_cycles(5)
      sleep 0.1

      gc_memory = current_memory_mb
      puts "  After GC: #{gc_memory} MB"

      # Memory should not increase significantly after GC
      expect(gc_memory).to be <= (post_init_memory + 50) # Allow some variance
    end

    it 'maintains performance under memory pressure' do
      # Create memory pressure by allocating large objects
      memory_pressure = []

      begin
        # Allocate ~100MB of memory pressure
        50.times do
          memory_pressure << Array.new(500_000) { rand.to_s }
        end

        # Test LazyInit performance under pressure
        test_class = Class.new do
          extend LazyInit

          lazy_attr_reader :computation do
            (1..10_000).sum
          end
        end

        instance = test_class.new

        # Measure performance under memory pressure
        iterations = 50_000
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        iterations.times { instance.computation }

        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        duration = end_time - start_time
        ops_per_second = iterations / duration

        puts "\nPerformance under memory pressure:"
        puts "  Operations: #{iterations}"
        puts "  Duration: #{duration.round(4)}s"
        puts "  Ops/sec: #{ops_per_second.round(0)}"

        # Should maintain reasonable performance (>100k ops/sec)
        expect(ops_per_second).to be > 100_000
        expect(instance.computation_computed?).to be true
      ensure
        # Clean up memory pressure
        memory_pressure.clear
        force_gc_cycles(3)
      end
    end

    it 'handles lazy_once memory management under pressure' do
      test_class = Class.new do
        include LazyInit

        def generate_data(id)
          lazy_once(max_entries: 100, ttl: 30) do
            Array.new(10_000) { "data_#{id}_#{rand(1000)}" }
          end
        end
      end

      instance = test_class.new
      initial_memory = current_memory_mb

      # Generate many different cached values
      1000.times do |i|
        instance.generate_data(i)

        # Force GC every 100 iterations
        next unless i % 100 == 0

        force_gc_cycles(1)

        # Check memory growth
        current_mem = current_memory_mb
        growth = current_mem - initial_memory

        # Memory growth should be bounded due to LRU eviction
        expect(growth).to be < 200, "Memory growth exceeded 200MB at iteration #{i}"
      end

      # Verify cache statistics
      stats = instance.lazy_once_statistics
      expect(stats[:total_entries]).to be <= 100 # Should not exceed max_entries

      puts "\nLazy_once memory management:"
      puts "  Final entries: #{stats[:total_entries]}"
      puts "  Total accesses: #{stats[:total_accesses]}"
      puts "  Memory growth: #{current_memory_mb - initial_memory} MB"
    end
  end
end
