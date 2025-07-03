#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../lib/lazy_init'

puts '=== LazyInit Fixed Thread Safety Verification ==='
puts "Ruby version: #{RUBY_VERSION}"
puts "Platform: #{RUBY_PLATFORM}"

# Test configuration
THREAD_COUNTS = [2, 4, 8, 16, 32, 50, 100]

class ThreadSafetyTester
  def initialize(description)
    @description = description
    @results = []
    @failures = []
  end

  def test(thread_count)
    puts "\n--- Testing #{@description} with #{thread_count} threads ---"

    results = []
    exceptions = []
    start_time = Time.now

    # Improved synchronization
    barrier = Mutex.new
    ready_count = 0
    ready_condition = ConditionVariable.new

    threads = thread_count.times.map do |i|
      Thread.new do
        barrier.synchronize do
          ready_count += 1
          if ready_count == thread_count
            ready_condition.broadcast
          else
            ready_condition.wait(barrier)
          end
        end

        begin
          result = yield(i)
          results << result
        rescue StandardError => e
          exceptions << { thread: i, error: e }
          results << :error
        end
      end
    end

    threads.each(&:join)
    end_time = Time.now

    analyze_results(thread_count, results, exceptions, end_time - start_time)
  end

  def summary
    puts "\n=== #{@description} SUMMARY ==="
    puts "Total tests: #{@results.size}"
    successes = @results.count { |r| r[:success] }
    puts "Successful: #{successes}/#{@results.size}"

    if @failures.any?
      puts "\nFAILURES DETECTED:"
      @failures.each do |failure|
        puts "  #{failure[:thread_count]} threads: #{failure[:unique_results]} unique results"
        puts "    Expected: 1, Got: #{failure[:unique_results]}"
        puts "    Sample results: #{failure[:results_sample]}"
      end
      false
    else
      puts '✓ ALL TESTS PASSED - THREAD SAFE'
      true
    end
  end

  private

  def analyze_results(thread_count, results, exceptions, duration)
    valid_results = results.reject { |r| r == :error }
    unique_results = valid_results.uniq

    puts "  Threads: #{thread_count}"
    puts "  Duration: #{'%.3f' % duration}s"
    puts "  Results: #{results.size} total, #{valid_results.size} valid"
    puts "  Unique results: #{unique_results.size}"
    puts "  Exceptions: #{exceptions.size}"

    if exceptions.any?
      puts '  EXCEPTIONS:'
      exceptions.first(3).each { |ex| puts "    Thread #{ex[:thread]}: #{ex[:error].message}" }
    end

    success = unique_results.size == 1 && exceptions.empty?
    puts "  STATUS: #{success ? '✓ THREAD-SAFE' : '✗ RACE CONDITION DETECTED'}"

    unless success
      @failures << {
        thread_count: thread_count,
        unique_results: unique_results.size,
        exceptions: exceptions.size,
        results_sample: unique_results.first(3)
      }
    end

    @results << {
      thread_count: thread_count,
      success: success,
      unique_results: unique_results.size,
      duration: duration,
      exceptions: exceptions.size
    }
  end
end

# === 1. Fixed Basic lazy_attr_reader Test ===
puts "\n" + '=' * 60
puts '1. FIXED BASIC LAZY_ATTR_READER THREAD SAFETY'
puts '=' * 60

basic_tester = ThreadSafetyTester.new('Fixed basic lazy_attr_reader')

THREAD_COUNTS.each do |thread_count|
  test_class = Class.new do
    extend LazyInit

    lazy_attr_reader :shared_computation do
      sleep(0.001) # Simulate potential race condition
      computation_id = Time.now.to_f * 1_000_000
      "result_#{computation_id.to_i}"
    end
  end

  instance = test_class.new

  basic_tester.test(thread_count) do |_thread_id|
    instance.shared_computation
  end
end

basic_success = basic_tester.summary

# === 2. Class Variable Thread Safety ===
puts "\n" + '=' * 60
puts '2. CLASS VARIABLE THREAD SAFETY'
puts '=' * 60

class_var_tester = ThreadSafetyTester.new('Class variable lazy_class_variable')

THREAD_COUNTS.each do |thread_count|
  test_class = Class.new do
    extend LazyInit

    lazy_class_variable :shared_resource do
      sleep(rand * 0.01) # Race condition opportunity
      resource_id = Time.now.to_f * 1_000_000
      "shared_resource_#{resource_id.to_i}"
    end
  end

  class_var_tester.test(thread_count) do |thread_id|
    # Mix of class and instance access
    if thread_id.even?
      test_class.shared_resource
    else
      test_class.new.shared_resource
    end
  end
end

class_var_success = class_var_tester.summary

# === 3. Dependency Injection Thread Safety ===
puts "\n" + '=' * 60
puts '3. DEPENDENCY INJECTION THREAD SAFETY'
puts '=' * 60

dependency_tester = ThreadSafetyTester.new('Dependency injection')

THREAD_COUNTS.each do |thread_count|
  test_class = Class.new do
    extend LazyInit

    lazy_attr_reader :base_config do
      sleep(rand * 0.005)
      config_id = Time.now.to_f * 1_000_000
      { id: config_id.to_i, url: "http://api-#{config_id.to_i}.com" }
    end

    lazy_attr_reader :database, depends_on: [:base_config] do
      sleep(rand * 0.005)
      "db_connection_#{base_config[:id]}"
    end

    lazy_attr_reader :api_client, depends_on: %i[base_config database] do
      sleep(rand * 0.005)
      "api_client_#{base_config[:id]}_#{database.split('_').last}"
    end
  end

  instance = test_class.new

  dependency_tester.test(thread_count) do |_thread_id|
    # All threads try to access the final dependent value
    instance.api_client
  end
end

dependency_success = dependency_tester.summary

# === 4. Exception Handling Thread Safety ===
puts "\n" + '=' * 60
puts '4. EXCEPTION HANDLING THREAD SAFETY'
puts '=' * 60

exception_tester = ThreadSafetyTester.new('Exception handling')

THREAD_COUNTS.each do |thread_count|
  test_class = Class.new do
    extend LazyInit

    lazy_attr_reader :failing_operation do
      sleep(rand * 0.01)
      raise StandardError, "Intentional failure #{Time.now.to_f}"
    end
  end

  instance = test_class.new

  exception_tester.test(thread_count) do |_thread_id|
    instance.failing_operation
    'unexpected_success'
  rescue StandardError => e
    e.message # Should be the same message for all threads
  end
end

exception_success = exception_tester.summary

# === 5. Stress Test - Mixed Operations ===
puts "\n" + '=' * 60
puts '5. STRESS TEST - MIXED OPERATIONS'
puts '=' * 60

stress_tester = ThreadSafetyTester.new('Mixed operations stress test')

# Single stress test with maximum thread count
test_class = Class.new do
  extend LazyInit

  lazy_attr_reader :config do
    sleep(rand * 0.02)
    base_id = Time.now.to_f * 1_000_000
    {
      id: base_id.to_i,
      timestamp: Time.now.to_f,
      random: rand(1_000_000)
    }
  end

  lazy_attr_reader :service_a, depends_on: [:config] do
    sleep(rand * 0.01)
    "service_a_#{config[:id]}"
  end

  lazy_attr_reader :service_b, depends_on: [:config] do
    sleep(rand * 0.01)
    "service_b_#{config[:id]}"
  end

  lazy_attr_reader :combined, depends_on: %i[service_a service_b] do
    sleep(rand * 0.01)
    "combined_#{service_a}_#{service_b}_#{config[:random]}"
  end

  lazy_class_variable :global_state do
    sleep(rand * 0.02)
    state_id = Time.now.to_f * 1_000_000
    "global_#{state_id.to_i}"
  end
end

# Test with multiple instances and high thread count
# instances = Array.new(10) { test_class.new }

shared_instance = test_class.new # Single shared instance

stress_tester.test(100) do |thread_id|
  operation = thread_id % 4

  case operation
  when 0
    shared_instance.config      # All threads same instance
  when 1
    shared_instance.combined    # All threads same instance
  when 2
    test_class.global_state     # Class level - already correct
  when 3
    shared_instance.service_a   # All threads same instance
  end
end

stress_success = stress_tester.summary

puts "\n" + '=' * 60
puts '6. LAZY_ONCE THREAD SAFETY'
puts '=' * 60

lazy_once_tester = ThreadSafetyTester.new('lazy_once')

test_class = Class.new do
  include LazyInit

  def shared_computation
    lazy_once do
      sleep(rand * 0.01)
      computation_id = Time.now.to_f * 1_000_000
      "lazy_once_#{computation_id.to_i}"
    end
  end
end

THREAD_COUNTS.each do |thread_count|
  instance = test_class.new

  lazy_once_tester.test(thread_count) do |_thread_id|
    instance.shared_computation
  end
end

lazy_once_success = lazy_once_tester.summary

# === FINAL VERIFICATION REPORT ===
puts "\n" + '=' * 80
puts 'FINAL THREAD SAFETY VERIFICATION REPORT'
puts '=' * 80

all_tests = [
  ['Basic lazy_attr_reader', basic_success],
  ['Class variables', class_var_success],
  ['Dependency injection', dependency_success],
  ['Exception handling', exception_success],
  ['Stress test', stress_success],
  ['lazy_once', lazy_once_success]
]

passed_tests = all_tests.count { |_, success| success }
total_tests = all_tests.size

puts 'SUMMARY:'
puts "  Passed: #{passed_tests}/#{total_tests} test categories"
puts "  Thread counts tested: #{THREAD_COUNTS.join(', ')}"
puts "  Maximum threads: #{THREAD_COUNTS.max}"
puts "  Ruby version: #{RUBY_VERSION}"

puts "\nDETAILS:"
all_tests.each do |name, success|
  status = success ? '✓ PASS' : '✗ FAIL'
  puts "  #{status} #{name}"
end

overall_success = passed_tests == total_tests

puts "\n" + '=' * 40
if overall_success
  puts '🎉 ALL THREAD SAFETY TESTS PASSED!'
  puts 'LazyInit gem is THREAD-SAFE across all features'
else
  puts '⚠️  THREAD SAFETY ISSUES DETECTED!'
  puts 'Some features may have race conditions'
end
puts '=' * 40

exit(overall_success ? 0 : 1)
