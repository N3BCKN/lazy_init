#!/usr/bin/env ruby
# frozen_string_literal: true

require 'benchmark/ips'
require_relative '../lib/lazy_init'

class LazyInitBenchmark
  VERSION = '2.0.0'

  def initialize
    @results = {}
    puts header
  end

  def run_all
    run_basic_patterns
    run_computational_complexity
    run_dependency_injection
    run_class_level_shared
    run_method_memoization
    run_timeout_overhead
    run_exception_handling
    run_thread_safety
    run_real_world_scenarios

    print_summary
  end

  private

  def header
    <<~HEADER
      ===================================================================
      LazyInit Performance Benchmark v#{VERSION} (Fixed Methodology)
      ===================================================================
      Ruby: #{RUBY_VERSION} (#{RUBY_ENGINE})
      Platform: #{RUBY_PLATFORM}
      Time: #{Time.now}
      ===================================================================
    HEADER
  end

  def benchmark_comparison(category, test_name, manual_impl, lazy_impl, warmup: true)
    puts "\n--- #{test_name} ---"

    # Enhanced warmup for more reliable results
    if warmup
      puts '  Warming up...'
      5.times do
        manual_impl.call
        lazy_impl.call
      end

      # Additional warmup for GC stabilization
      GC.start
      sleep 0.01
    end

    # Run benchmark with more iterations for stability
    suite = Benchmark.ips do |x|
      x.config(time: 5, warmup: 2)
      x.report('Manual', &manual_impl)
      x.report('LazyInit', &lazy_impl)
      x.compare!
    end

    # Extract results
    manual_ips = suite.entries[0].ips
    lazy_ips = suite.entries[1].ips

    # Store results
    store_result(category, test_name, manual_ips, lazy_ips)

    # Print formatted results
    puts "Manual:   #{format_ips(manual_ips)}"
    puts "LazyInit: #{format_ips(lazy_ips)}"
    puts "Ratio:    #{(manual_ips / lazy_ips).round(2)}x"

    [manual_ips, lazy_ips]
  end

  def store_result(category, test_name, manual_ips, lazy_ips)
    @results[category] ||= {}
    @results[category][test_name] = {
      manual: manual_ips,
      lazy_init: lazy_ips,
      ratio: (manual_ips / lazy_ips).round(2),
      overhead_percent: ((lazy_ips / manual_ips - 1) * 100).round(1)
    }
  end

  def format_ips(ips)
    case ips
    when 0...1_000
      "#{ips.round(0)} i/s"
    when 1_000...1_000_000
      "#{(ips / 1_000.0).round(1)}K i/s"
    else
      "#{(ips / 1_000_000.0).round(2)}M i/s"
    end
  end

  # ========================================
  # BENCHMARK SCENARIOS
  # ========================================

  def run_basic_patterns
    puts "\n" + '=' * 30
    puts '1. BASIC LAZY INITIALIZATION PATTERNS'
    puts '=' * 30

    # Hot path performance - fair comparison after both are initialized
    manual_basic = create_manual_basic
    lazy_basic = create_lazy_basic

    # Pre-initialize both for hot path test
    manual_basic.expensive_value
    lazy_basic.expensive_value

    benchmark_comparison(
      'Basic Patterns',
      'Hot Path (after initialization)',
      -> { manual_basic.expensive_value },
      -> { lazy_basic.expensive_value }
    )

    # Cold start performance - fresh instances each time
    benchmark_comparison(
      'Basic Patterns',
      'Cold Start (new instances)',
      -> { create_manual_basic.expensive_value },
      -> { create_lazy_basic.expensive_value },
      warmup: false
    )

    # Memory overhead test - check after many instances
    benchmark_comparison(
      'Basic Patterns',
      'Memory Overhead (100 instances)',
      -> { 100.times { create_manual_basic } },
      -> { 100.times { create_lazy_basic } },
      warmup: false
    )
  end

  def run_computational_complexity
    puts "\n" + '=' * 30
    puts '2. COMPUTATIONAL COMPLEXITY SCENARIOS'
    puts '=' * 30

    # Light computation
    manual_light = create_manual_light
    lazy_light = create_lazy_light

    benchmark_comparison(
      'Computational Complexity',
      'Lightweight (sum 1..10)',
      -> { manual_light.light_computation },
      -> { lazy_light.light_computation }
    )

    # Medium computation
    manual_medium = create_manual_medium
    lazy_medium = create_lazy_medium

    benchmark_comparison(
      'Computational Complexity',
      'Medium (map+sum 1..1000)',
      -> { manual_medium.medium_computation },
      -> { lazy_medium.medium_computation }
    )

    # Heavy computation
    manual_heavy = create_manual_heavy
    lazy_heavy = create_lazy_heavy

    benchmark_comparison(
      'Computational Complexity',
      'Heavy (filter+sqrt 1..10000)',
      -> { manual_heavy.heavy_computation },
      -> { lazy_heavy.heavy_computation }
    )
  end

  def run_dependency_injection
    puts "\n" + '=' * 30
    puts '3. DEPENDENCY INJECTION PERFORMANCE'
    puts '=' * 30

    # Simple dependencies
    manual_deps = create_manual_deps
    lazy_deps = create_lazy_deps

    benchmark_comparison(
      'Dependency Injection',
      'Simple Dependencies',
      -> { manual_deps.database },
      -> { lazy_deps.database }
    )

    # Complex dependencies
    manual_complex = create_manual_complex_deps
    lazy_complex = create_lazy_complex_deps

    benchmark_comparison(
      'Dependency Injection',
      'Complex Dependencies',
      -> { manual_complex.service },
      -> { lazy_complex.service }
    )

    # Mixed access patterns
    manual_mixed = create_manual_complex_deps
    lazy_mixed = create_lazy_complex_deps

    benchmark_comparison(
      'Dependency Injection',
      'Mixed Access Pattern',
      lambda {
        manual_mixed.config
        manual_mixed.database
        manual_mixed.service
      },
      lambda {
        lazy_mixed.config
        lazy_mixed.database
        lazy_mixed.service
      }
    )
  end

  def run_class_level_shared
    puts "\n" + '=' * 30
    puts '4. CLASS-LEVEL SHARED RESOURCES'
    puts '=' * 30

    # FIXED: Don't pre-initialize class variables
    benchmark_comparison(
      'Class-Level Resources',
      'Shared Resources (Cold)',
      -> { create_manual_class_var.shared_resource },
      -> { create_lazy_class_var.shared_resource }
    )

    # Hot path for class variables
    manual_class_hot = create_manual_class_var
    lazy_class_hot = create_lazy_class_var

    # Initialize both
    manual_class_hot.shared_resource
    lazy_class_hot.shared_resource

    benchmark_comparison(
      'Class-Level Resources',
      'Shared Resources (Hot)',
      -> { manual_class_hot.shared_resource },
      -> { lazy_class_hot.shared_resource }
    )

    # Multiple instances accessing same class variable
    benchmark_comparison(
      'Class-Level Resources',
      'Multiple Instances Access',
      lambda {
        instances = 5.times.map { create_manual_class_var }
        instances.each(&:shared_resource)
      },
      lambda {
        instances = 5.times.map { create_lazy_class_var }
        instances.each(&:shared_resource)
      }
    )
  end

  def run_method_memoization
    puts "\n" + '=' * 30
    puts '5. METHOD-LOCAL MEMOIZATION'
    puts '=' * 30

    # FIXED: Fair comparison with same caching behavior
    manual_memo = create_manual_memo
    lazy_memo = create_lazy_memo

    # Test with same key (cache hit scenario)
    benchmark_comparison(
      'Method Memoization',
      'Same Key Cache Hit',
      -> { manual_memo.expensive_calc(100) },
      -> { lazy_memo.expensive_calc(100) }
    )

    # Test with different keys (cache miss scenario)
    key_counter = 0
    benchmark_comparison(
      'Method Memoization',
      'Different Keys',
      lambda {
        key_counter += 1
        create_manual_memo.expensive_calc(key_counter)
      },
      lambda {
        key_counter += 1
        create_lazy_memo.expensive_calc(key_counter)
      },
      warmup: false
    )

    # Test cache performance with many keys
    benchmark_comparison(
      'Method Memoization',
      'Many Keys Performance',
      lambda {
        memo = create_manual_memo
        100.times { |i| memo.expensive_calc(i) }
      },
      lambda {
        memo = create_lazy_memo
        100.times { |i| memo.expensive_calc(i) }
      }
    )
  end

  def run_timeout_overhead
    puts "\n" + '=' * 30
    puts '6. TIMEOUT OVERHEAD'
    puts '=' * 30

    no_timeout = create_no_timeout
    with_timeout = create_with_timeout

    benchmark_comparison(
      'Timeout Support',
      'No Timeout vs With Timeout',
      -> { no_timeout.quick_operation },
      -> { with_timeout.quick_operation }
    )

    # Test timeout configuration overhead
    benchmark_comparison(
      'Timeout Support',
      'Timeout Configuration Cost',
      -> { create_no_timeout.quick_operation },
      -> { create_with_timeout.quick_operation },
      warmup: false
    )
  end

  def run_exception_handling
    puts "\n" + '=' * 30
    puts '7. EXCEPTION HANDLING OVERHEAD'
    puts '=' * 30

    # FIXED: Same exception handling behavior
    manual_exception = create_manual_exception
    lazy_exception = create_lazy_exception

    benchmark_comparison(
      'Exception Handling',
      'Exception Recovery',
      -> { manual_exception.failing_method },
      -> { lazy_exception.failing_method }
    )

    # Test exception caching behavior
    manual_exception_cached = create_manual_exception_cached
    lazy_exception_cached = create_lazy_exception_cached

    benchmark_comparison(
      'Exception Handling',
      'Exception Caching',
      lambda {
        begin
          manual_exception_cached.always_fails
        rescue StandardError
          # Exception not cached in manual approach
        end
      },
      lambda {
        begin
          lazy_exception_cached.always_fails
        rescue StandardError
          # Exception cached in LazyInit
        end
      }
    )
  end

  def run_thread_safety
    puts "\n" + '=' * 30
    puts '8. THREAD SAFETY PERFORMANCE'
    puts '=' * 30

    # This is where LazyInit should shine - testing concurrent access
    manual_concurrent = create_manual_concurrent
    lazy_concurrent = create_lazy_concurrent

    benchmark_comparison(
      'Thread Safety',
      'Concurrent Access (10 threads)',
      lambda {
        threads = 10.times.map do
          Thread.new { manual_concurrent.thread_safe_value }
        end
        threads.each(&:join)
      },
      lambda {
        threads = 10.times.map do
          Thread.new { lazy_concurrent.thread_safe_value }
        end
        threads.each(&:join)
      }
    )

    # Test under high contention
    benchmark_comparison(
      'Thread Safety',
      'High Contention (50 threads)',
      lambda {
        instance = create_manual_concurrent
        threads = 50.times.map do
          Thread.new { instance.thread_safe_value }
        end
        threads.each(&:join)
      },
      lambda {
        instance = create_lazy_concurrent
        threads = 50.times.map do
          Thread.new { instance.thread_safe_value }
        end
        threads.each(&:join)
      }
    )

    # Test reset safety under concurrent access
    benchmark_comparison(
      'Thread Safety',
      'Concurrent Reset Safety',
      lambda {
        instance = create_manual_concurrent
        threads = []

        # Readers
        10.times do
          threads << Thread.new do
            20.times { instance.resettable_value }
          end
        end

        # Resetters
        2.times do
          threads << Thread.new do
            5.times do
              sleep 0.001
              instance.reset_resettable_value!
            end
          end
        end

        threads.each(&:join)
      },
      lambda {
        instance = create_lazy_concurrent
        threads = []

        # Readers
        10.times do
          threads << Thread.new do
            20.times { instance.resettable_value }
          end
        end

        # Resetters
        2.times do
          threads << Thread.new do
            5.times do
              sleep 0.001
              instance.reset_resettable_value!
            end
          end
        end

        threads.each(&:join)
      }
    )
  end

  def run_real_world_scenarios
    puts "\n" + '=' * 30
    puts '9. REAL-WORLD SCENARIOS'
    puts '=' * 30

    manual_webapp = create_manual_webapp
    lazy_webapp = create_lazy_webapp

    benchmark_comparison(
      'Real-World',
      'Web Application Stack',
      -> { manual_webapp.application },
      -> { lazy_webapp.application }
    )

    # Rails-like service pattern
    benchmark_comparison(
      'Real-World',
      'Service Container Pattern',
      lambda {
        container = create_manual_service_container
        container.user_service
        container.notification_service
        container.payment_service
      },
      lambda {
        container = create_lazy_service_container
        container.user_service
        container.notification_service
        container.payment_service
      }
    )

    # Background job pattern
    benchmark_comparison(
      'Real-World',
      'Background Job Setup',
      lambda {
        job = create_manual_background_job
        job.setup_dependencies
        job.process_data('test_data')
      },
      lambda {
        job = create_lazy_background_job
        job.setup_dependencies
        job.process_data('test_data')
      }
    )
  end

  # ========================================
  # FACTORY METHODS (FIXED)
  # ========================================

  def create_manual_basic
    Class.new do
      def expensive_value
        @expensive_value ||= "computed_value_#{rand(1000)}"
      end
    end.new
  end

  def create_lazy_basic
    Class.new do
      extend LazyInit
      lazy_attr_reader :expensive_value do
        "computed_value_#{rand(1000)}"
      end
    end.new
  end

  def create_manual_light
    Class.new do
      def light_computation
        @light_computation ||= (1..10).sum
      end
    end.new
  end

  def create_lazy_light
    Class.new do
      extend LazyInit
      lazy_attr_reader :light_computation do
        (1..10).sum
      end
    end.new
  end

  def create_manual_medium
    Class.new do
      def medium_computation
        @medium_computation ||= (1..1000).map { |i| i * 2 }.sum
      end
    end.new
  end

  def create_lazy_medium
    Class.new do
      extend LazyInit
      lazy_attr_reader :medium_computation do
        (1..1000).map { |i| i * 2 }.sum
      end
    end.new
  end

  def create_manual_heavy
    Class.new do
      def heavy_computation
        @heavy_computation ||= (1..10_000).select(&:even?).map { |i| Math.sqrt(i) }.sum
      end
    end.new
  end

  def create_lazy_heavy
    Class.new do
      extend LazyInit
      lazy_attr_reader :heavy_computation do
        (1..10_000).select(&:even?).map { |i| Math.sqrt(i) }.sum
      end
    end.new
  end

  def create_manual_deps
    Class.new do
      def config
        @config ||= { database_url: 'postgresql://localhost/test' }
      end

      def database
        @database ||= begin
          config
          "Connected to: #{config[:database_url]}"
        end
      end
    end.new
  end

  def create_lazy_deps
    Class.new do
      extend LazyInit

      lazy_attr_reader :config do
        { database_url: 'postgresql://localhost/test' }
      end

      lazy_attr_reader :database, depends_on: [:config] do
        "Connected to: #{config[:database_url]}"
      end
    end.new
  end

  def create_manual_complex_deps
    Class.new do
      def config
        @config ||= { db_url: 'postgresql://localhost', api_key: 'test123', debug: false }
      end

      def database
        @database ||= begin
          config
          "DB: #{config[:db_url]}"
        end
      end

      def api_client
        @api_client ||= begin
          config
          database
          "API: #{config[:api_key]} using #{database}"
        end
      end

      def logger
        @logger ||= begin
          config
          "Logger: debug=#{config[:debug]}"
        end
      end

      def service
        @service ||= begin
          api_client
          logger
          "Service: #{api_client} with #{logger}"
        end
      end
    end.new
  end

  def create_lazy_complex_deps
    Class.new do
      extend LazyInit

      lazy_attr_reader :config do
        { db_url: 'postgresql://localhost', api_key: 'test123', debug: false }
      end

      lazy_attr_reader :database, depends_on: [:config] do
        "DB: #{config[:db_url]}"
      end

      lazy_attr_reader :api_client, depends_on: %i[config database] do
        "API: #{config[:api_key]} using #{database}"
      end

      lazy_attr_reader :logger, depends_on: [:config] do
        "Logger: debug=#{config[:debug]}"
      end

      lazy_attr_reader :service, depends_on: %i[api_client logger] do
        "Service: #{api_client} with #{logger}"
      end
    end.new
  end

  # FIXED: Class variable tests without pre-initialization
  def create_manual_class_var
    # Create fresh class each time to avoid shared state
    Class.new do
      def self.shared_resource
        @@shared_resource ||= "Shared resource #{rand(1000)}"
      end

      def shared_resource
        self.class.shared_resource
      end
    end.new
  end

  def create_lazy_class_var
    # Create fresh class each time without pre-initialization
    Class.new do
      extend LazyInit

      lazy_class_variable :shared_resource do
        "Shared resource #{rand(1000)}"
      end
    end.new
  end

  # FIXED: Method memoization with fair comparison
  def create_manual_memo
    Class.new do
      def expensive_calc(key)
        @memo ||= {}
        @memo[key] ||= "computed_#{key}_#{rand(1000)}"
      end
    end.new
  end

  def create_lazy_memo
    Class.new do
      include LazyInit

      def initialize
        @memo_cache = {}
      end

      def expensive_calc(key)
        # Fair comparison: cache per key like manual version
        return @memo_cache[key] if @memo_cache.key?(key)

        @memo_cache[key] = lazy_once { "computed_#{key}_#{rand(1000)}" }
      end
    end.new
  end

  def create_no_timeout
    Class.new do
      extend LazyInit

      lazy_attr_reader :quick_operation do
        (1..10).sum
      end
    end.new
  end

  def create_with_timeout
    Class.new do
      extend LazyInit

      lazy_attr_reader :quick_operation, timeout: 5 do
        (1..10).sum
      end
    end.new
  end

  # FIXED: Exception handling with same behavior
  def create_manual_exception
    Class.new do
      def failing_method
        @failing_method ||= begin
          raise StandardError, 'Always fails'
        rescue StandardError
          'recovered'
        end
      end
    end.new
  end

  def create_lazy_exception
    Class.new do
      extend LazyInit

      lazy_attr_reader :failing_method do
        raise StandardError, 'Always fails'
      rescue StandardError
        'recovered'
      end
    end.new
  end

  # NEW: Exception caching behavior tests
  def create_manual_exception_cached
    Class.new do
      def always_fails
        # Manual approach doesn't cache exceptions
        raise StandardError, 'Always fails'
      end
    end.new
  end

  def create_lazy_exception_cached
    Class.new do
      extend LazyInit

      lazy_attr_reader :always_fails do
        raise StandardError, 'Always fails'
      end
    end.new
  end

  # NEW: Thread safety test implementations
  def create_manual_concurrent
    Class.new do
      def initialize
        @mutex = Mutex.new
        @reset_mutex = Mutex.new
      end

      def thread_safe_value
        return @thread_safe_value if defined?(@thread_safe_value)

        @mutex.synchronize do
          return @thread_safe_value if defined?(@thread_safe_value)

          @thread_safe_value = "thread_safe_#{rand(1000)}"
        end
      end

      def resettable_value
        return @resettable_value if defined?(@resettable_value)

        @mutex.synchronize do
          return @resettable_value if defined?(@resettable_value)

          @resettable_value = "resettable_#{rand(1000)}"
        end
      end

      def reset_resettable_value!
        @reset_mutex.synchronize do
          @mutex.synchronize do
            remove_instance_variable(:@resettable_value) if defined?(@resettable_value)
          end
        end
      end
    end.new
  end

  def create_lazy_concurrent
    Class.new do
      extend LazyInit

      lazy_attr_reader :thread_safe_value do
        "thread_safe_#{rand(1000)}"
      end

      lazy_attr_reader :resettable_value do
        "resettable_#{rand(1000)}"
      end
    end.new
  end

  def create_manual_webapp
    Class.new do
      def config
        @config ||= {
          database_url: ENV['DATABASE_URL'] || 'postgresql://localhost/app',
          redis_url: ENV['REDIS_URL'] || 'redis://localhost:6379',
          api_key: ENV['API_KEY'] || 'test_key',
          debug: ENV['DEBUG'] == 'true'
        }
      end

      def database
        @database ||= begin
          config
          "Database connection: #{config[:database_url]}"
        end
      end

      def cache
        @cache ||= begin
          config
          "Redis connection: #{config[:redis_url]}"
        end
      end

      def api_client
        @api_client ||= begin
          config
          "API client with key: #{config[:api_key]}"
        end
      end

      def logger
        @logger ||= begin
          config
          "Logger (debug: #{config[:debug]})"
        end
      end

      def application
        @application ||= begin
          database
          cache
          api_client
          logger
          'Application initialized with all services'
        end
      end
    end.new
  end

  def create_lazy_webapp
    Class.new do
      extend LazyInit

      lazy_attr_reader :config do
        {
          database_url: ENV['DATABASE_URL'] || 'postgresql://localhost/app',
          redis_url: ENV['REDIS_URL'] || 'redis://localhost:6379',
          api_key: ENV['API_KEY'] || 'test_key',
          debug: ENV['DEBUG'] == 'true'
        }
      end

      lazy_attr_reader :database, depends_on: [:config] do
        "Database connection: #{config[:database_url]}"
      end

      lazy_attr_reader :cache, depends_on: [:config] do
        "Redis connection: #{config[:redis_url]}"
      end

      lazy_attr_reader :api_client, depends_on: [:config] do
        "API client with key: #{config[:api_key]}"
      end

      lazy_attr_reader :logger, depends_on: [:config] do
        "Logger (debug: #{config[:debug]})"
      end

      lazy_attr_reader :application, depends_on: %i[database cache api_client logger] do
        'Application initialized with all services'
      end
    end.new
  end

  # NEW: Additional realistic test cases
  def create_manual_service_container
    Class.new do
      def database_config
        @database_config ||= { url: 'postgresql://localhost/app' }
      end

      def redis_config
        @redis_config ||= { url: 'redis://localhost:6379' }
      end

      def user_service
        @user_service ||= begin
          database_config
          "UserService using #{database_config[:url]}"
        end
      end

      def notification_service
        @notification_service ||= begin
          redis_config
          user_service
          "NotificationService using #{redis_config[:url]} and #{user_service}"
        end
      end

      def payment_service
        @payment_service ||= begin
          user_service
          "PaymentService using #{user_service}"
        end
      end
    end.new
  end

  def create_lazy_service_container
    Class.new do
      extend LazyInit

      lazy_attr_reader :database_config do
        { url: 'postgresql://localhost/app' }
      end

      lazy_attr_reader :redis_config do
        { url: 'redis://localhost:6379' }
      end

      lazy_attr_reader :user_service, depends_on: [:database_config] do
        "UserService using #{database_config[:url]}"
      end

      lazy_attr_reader :notification_service, depends_on: %i[redis_config user_service] do
        "NotificationService using #{redis_config[:url]} and #{user_service}"
      end

      lazy_attr_reader :payment_service, depends_on: [:user_service] do
        "PaymentService using #{user_service}"
      end
    end.new
  end

  def create_manual_background_job
    Class.new do
      def setup_dependencies
        processor
        storage
        logger
      end

      def processor
        @processor ||= 'DataProcessor initialized'
      end

      def storage
        @storage ||= begin
          processor
          "StorageService using #{processor}"
        end
      end

      def logger
        @logger ||= 'Logger initialized'
      end

      def process_data(data)
        setup_dependencies
        "Processing #{data} with #{processor}, #{storage}, #{logger}"
      end
    end.new
  end

  def create_lazy_background_job
    Class.new do
      extend LazyInit

      lazy_attr_reader :processor do
        'DataProcessor initialized'
      end

      lazy_attr_reader :storage, depends_on: [:processor] do
        "StorageService using #{processor}"
      end

      lazy_attr_reader :logger do
        'Logger initialized'
      end

      def setup_dependencies
        processor
        storage
        logger
      end

      def process_data(data)
        setup_dependencies
        "Processing #{data} with #{processor}, #{storage}, #{logger}"
      end
    end.new
  end

  # ========================================
  # RESULTS & SUMMARY (Enhanced)
  # ========================================

  def print_summary
    puts "\n" + '=' * 30
    puts 'BENCHMARK SUMMARY (Fixed Methodology)'
    puts '=' * 30

    print_detailed_results
    print_performance_analysis
    print_thread_safety_analysis
    print_recommendations
  end

  def print_detailed_results
    puts "\nDetailed Results:"
    puts '-' * 30

    @results.each do |category, tests|
      puts "\n#{category}:"

      tests.each do |test_name, data|
        overhead_str = if data[:overhead_percent] < -20
                         "#{(-data[:overhead_percent]).round(1)}% faster"
                       elsif data[:ratio] < 1.2
                         'similar performance'
                       else
                         "#{data[:ratio]}x slower"
                       end

        puts "  #{test_name}:"
        puts "    Manual:   #{format_ips(data[:manual])}"
        puts "    LazyInit: #{format_ips(data[:lazy_init])}"
        puts "    Result:   #{overhead_str}"
      end
    end
  end

  def print_performance_analysis
    puts "\n" + '=' * 30
    puts 'PERFORMANCE ANALYSIS'
    puts '=' * 30

    all_ratios = @results.values.flat_map(&:values).map { |data| data[:ratio] }
    avg_ratio = (all_ratios.sum / all_ratios.size).round(2)
    min_ratio = all_ratios.min.round(2)
    max_ratio = all_ratios.max.round(2)

    puts "\nOverall Performance Impact:"
    puts "  Average overhead: #{avg_ratio}x"
    puts "  Best case: #{min_ratio}x slower"
    puts "  Worst case: #{max_ratio}x slower"

    # Analyze hot path vs cold start
    basic = @results['Basic Patterns']
    if basic
      hot_path = basic['Hot Path (after initialization)']
      cold_start = basic['Cold Start (new instances)']

      if hot_path && cold_start
        puts "\nHot Path vs Cold Start:"
        puts "  Hot path overhead: #{hot_path[:ratio]}x"
        puts "  Cold start overhead: #{cold_start[:ratio]}x"

        if hot_path[:ratio] < 1.5
          puts '  ✓ Excellent hot path performance!'
        elsif cold_start[:ratio] > hot_path[:ratio] * 3
          puts '  ⚠ Cold start overhead is significant'
        end
      end
    end

    # Analyze computational complexity impact
    computational = @results['Computational Complexity']
    return unless computational

    light_ratio = computational['Lightweight (sum 1..10)']&.[](:ratio)
    heavy_ratio = computational['Heavy (filter+sqrt 1..10000)']&.[](:ratio)

    return unless light_ratio && heavy_ratio

    puts "\nComputational Complexity Impact:"
    puts "  Light computation overhead: #{light_ratio}x"
    puts "  Heavy computation overhead: #{heavy_ratio}x"

    if (light_ratio - heavy_ratio).abs < 0.5
      puts '  • Overhead is consistent across complexity levels'
    elsif light_ratio > heavy_ratio
      puts '  • Better suited for expensive operations'
    end
  end

  def print_thread_safety_analysis
    thread_safety = @results['Thread Safety']
    return unless thread_safety

    puts "\n" + '=' * 50
    puts 'THREAD SAFETY ANALYSIS'
    puts '=' * 50

    concurrent = thread_safety['Concurrent Access (10 threads)']
    high_contention = thread_safety['High Contention (50 threads)']
    reset_safety = thread_safety['Concurrent Reset Safety']

    if concurrent
      puts "\nConcurrent Access Performance:"
      puts "  10 threads: #{concurrent[:ratio]}x slower"
      puts "  50 threads: #{high_contention[:ratio]}x slower" if high_contention

      if concurrent[:ratio] < 2.0
        puts '  ✓ Good concurrent performance!'
      elsif concurrent[:ratio] < 5.0
        puts '  ⚠ Moderate concurrent overhead'
      else
        puts '  ❌ High concurrent overhead'
      end
    end

    return unless reset_safety

    puts "\nReset Safety:"
    puts "  Concurrent reset overhead: #{reset_safety[:ratio]}x"

    if reset_safety[:ratio] < 10.0
      puts '  ✓ Thread-safe resets are reasonably efficient'
    else
      puts '  ⚠ Thread-safe resets have significant overhead'
    end
  end

  def print_recommendations
    puts "\n" + '=' * 20
    puts 'RECOMMENDATIONS'
    puts '=' * 20

    all_ratios = @results.values.flat_map(&:values).map { |data| data[:ratio] }
    avg_ratio = all_ratios.sum / all_ratios.size

    basic = @results['Basic Patterns']
    hot_path_ratio = basic&.[]('Hot Path (after initialization)')&.[](:ratio)

    puts "\nWhen to use LazyInit:"

    if hot_path_ratio && hot_path_ratio < 1.5
      puts '✓ Hot path performance is excellent - safe for frequent access'
      puts '✓ Thread safety benefits outweigh minimal overhead'
      puts '✓ Recommended for most lazy initialization scenarios'
    elsif avg_ratio > 10
      puts '⚠ Only for very expensive initialization (>10ms)'
      puts '⚠ When thread safety is absolutely critical'
      puts '⚠ Complex dependency chains only'
    elsif avg_ratio > 5
      puts '• Expensive initialization (>1ms)'
      puts '• Multi-threaded applications'
      puts '• When manual synchronization is error-prone'
    else
      puts '• Most lazy initialization scenarios'
      puts '• Thread-safe applications'
      puts '• Clean dependency management needed'
    end

    puts "\nKey Findings:"
    puts "• Hot path overhead is minimal (#{hot_path_ratio}x)" if hot_path_ratio && hot_path_ratio < 2.0

    thread_safety = @results['Thread Safety']
    if thread_safety
      concurrent_ratio = thread_safety['Concurrent Access (10 threads)']&.[](:ratio)
      puts '• Good performance under concurrent access' if concurrent_ratio && concurrent_ratio < 3.0
    end

    puts '• Trade-off: initialization cost vs runtime safety'
    puts '• Consider cold start impact for short-lived processes'

    puts "\n" + '=' * 50
    puts 'BENCHMARK COMPLETED (Fixed Methodology)'
    puts '=' * 50
  end
end

# Run the benchmark
if __FILE__ == $0
  begin
    benchmark = LazyInitBenchmark.new
    benchmark.run_all
  rescue StandardError => e
    puts "Benchmark failed: #{e.message}"
    puts e.backtrace.first(10)
    exit 1
  end
end
