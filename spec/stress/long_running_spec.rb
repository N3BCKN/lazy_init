require_relative './stress_helper'

RSpec.describe 'Long-running Stability Tests', :stress do
  def run_for_duration(duration_seconds)
    start_time = Time.now
    iteration = 0

    while (Time.now - start_time) < duration_seconds
      yield(iteration)
      iteration += 1

      # Small delay to prevent CPU spinning
      sleep(0.001) if iteration % 1000 == 0
    end

    iteration
  end

  describe 'extended runtime stability' do
    it 'maintains thread safety over extended periods' do
      test_class = Class.new do
        extend LazyInit

        lazy_attr_reader :counter do
          @@global_counter ||= 0
          @@global_counter += 1
        end

        lazy_attr_reader :timestamp do
          Time.now.to_f
        end
      end

      results = []
      errors = []
      mutex = Mutex.new

      # Run for 30 seconds with high concurrency
      duration = ENV['LONG_TEST_DURATION']&.to_i || 30
      thread_count = 10

      puts "\nRunning long-term stability test for #{duration} seconds..."

      threads = thread_count.times.map do |thread_id|
        Thread.new do
          thread_results = []
          thread_errors = []

          iterations = run_for_duration(duration) do |iteration|
            instance = test_class.new
            counter_value = instance.counter
            timestamp_value = instance.timestamp

            thread_results << {
              thread: thread_id,
              iteration: iteration,
              counter: counter_value,
              timestamp: timestamp_value,
              time: Time.now.to_f
            }

            # Verify computed state
            expect(instance.counter_computed?).to be true
            expect(instance.timestamp_computed?).to be true

          rescue StandardError => e
            thread_errors << {
              thread: thread_id,
              iteration: iteration,
              error: e.message,
              time: Time.now.to_f
            }
          end

          mutex.synchronize do
            results.concat(thread_results)
            errors.concat(thread_errors)
          end

          thread_results.size
        end
      end

      iterations_per_thread = threads.map(&:value)
      total_iterations = iterations_per_thread.sum

      puts 'Completed stability test:'
      puts "  Duration: #{duration}s"
      puts "  Threads: #{thread_count}"
      puts "  Total iterations: #{total_iterations}"
      puts "  Iterations per thread: #{iterations_per_thread}"
      puts "  Errors: #{errors.size}"
      puts "  Success rate: #{((total_iterations - errors.size).to_f / total_iterations * 100).round(2)}%"

      # Analyze results
      counter_values = results.map { |r| r[:counter] }.uniq.sort

      expect(errors.size).to eq(0), "Unexpected errors: #{errors.first(5)}"
      expect(counter_values).to eq(counter_values.sort), 'Counter values not sequential'
      expect(total_iterations).to be > 1000, 'Too few iterations for meaningful test'

      # Verify thread safety - all instances should have unique counters
      # but each individual access should be consistent
      results_by_instance = results.group_by { |r| [r[:thread], r[:counter]] }
      results_by_instance.each do |_key, instance_results|
        timestamps = instance_results.map { |r| r[:timestamp] }.uniq
        expect(timestamps.size).to eq(1), 'Timestamp should be cached per instance'
      end
    end

    it 'handles memory management over extended periods' do
      test_class = Class.new do
        include LazyInit
        extend LazyInit

        lazy_attr_reader :session_data do
          { session_id: rand(1_000_000), data: Array.new(1000) { rand.to_s } }
        end

        def cached_computation(key)
          lazy_once(max_entries: 50, ttl: 5) do
            Array.new(100) { "#{key}_#{rand(1000)}" }
          end
        end
      end

      initial_memory = GC.stat[:heap_allocated_pages]
      memory_samples = []

      duration = ENV['LONG_TEST_DURATION']&.to_i || 30
      puts "\nRunning memory management test for #{duration} seconds..."

      iterations = run_for_duration(duration) do |iteration|
        # Create instances and use them
        instance = test_class.new
        instance.session_data
        instance.cached_computation(iteration % 100) # Limited key space

        # Sample memory usage every 1000 iterations
        if iteration % 1000 == 0
          GC.start
          current_memory = GC.stat[:heap_allocated_pages]
          memory_samples << {
            iteration: iteration,
            memory_pages: current_memory,
            time: Time.now.to_f
          }

          # Check lazy_once statistics
          stats = instance.lazy_once_statistics
          puts "  Iteration #{iteration}: Memory pages: #{current_memory}, Cache entries: #{stats[:total_entries]}"
        end

        # Reset some instances occasionally to test cleanup
        if iteration % 5000 == 0
          instance.reset_session_data!
          instance.clear_lazy_once_values!
        end
      end

      final_memory = GC.stat[:heap_allocated_pages]
      memory_growth = final_memory - initial_memory

      puts 'Memory management results:'
      puts "  Iterations: #{iterations}"
      puts "  Initial memory: #{initial_memory} pages"
      puts "  Final memory: #{final_memory} pages"
      puts "  Growth: #{memory_growth} pages"
      puts "  Growth rate: #{(memory_growth.to_f / iterations * 1000).round(4)} pages/1k iterations"

      # Memory growth should be bounded
      expect(memory_growth).to be < 1000, 'Excessive memory growth detected'

      # Memory usage should stabilize (not grow linearly)
      if memory_samples.size >= 5
        recent_samples = memory_samples.last(5)
        memory_variance = recent_samples.map { |s| s[:memory_pages] }.max -
                          recent_samples.map { |s| s[:memory_pages] }.min

        expect(memory_variance).to be < 500, 'Memory usage not stabilized'
      end
    end
  end
end
