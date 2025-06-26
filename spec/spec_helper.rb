# frozen_string_literal: true

require 'lazy_init'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on Module and main
  config.disable_monkey_patching!

  # Use expect syntax
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Configure output
  config.color = true
  config.formatter = :documentation

  # Random order to catch test dependencies
  config.order = :random
  Kernel.srand config.seed

  # Filter by focus tags
  config.filter_run_when_matching :focus

  # Shared contexts and helpers
  config.shared_context_metadata_behavior = :apply_to_host_groups

  # Helper methods
  config.include Module.new {
    # Helper to create a new test class
    def create_test_class(&block)
      Class.new do
        extend LazyInit
        class_eval(&block) if block
      end
    end

    # Helper to measure time with better precision
    def measure_time(&block)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      block.call
      Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
    end

    # Helper to run code in multiple threads and collect results
    def run_in_threads(count = 10, &block)
      results = []
      mutex = Mutex.new
      
      threads = count.times.map do |i|
        Thread.new do
          result = block.call(i)
          mutex.synchronize { results << result }
        end
      end
      
      threads.each(&:join)
      results
    end

    # Helper to wait for a condition with timeout
    def wait_for(timeout: 1.0, interval: 0.01)
      start_time = Time.now
      while Time.now - start_time < timeout
        return true if yield
        sleep(interval)
      end
      false
    end
  }
end