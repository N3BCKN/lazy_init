#!/usr/bin/env ruby
# frozen_string_literal: true

require 'benchmark/ips'
require_relative '../lib/lazy_init'

class LazyInitBenchmark
  VERSION = '1.0.0'

  def initialize
    @results = {}
    puts header
  end

  def run_all
    run_basic_patterns
    run_computational_complexity
    run_dependency_injection
    # run_conditional_loading
    run_class_level_shared
    run_method_memoization
    run_timeout_overhead
    run_exception_handling
    run_real_world_scenarios

    print_summary
  end

  private

  def header
    <<~HEADER
      ===================================================================
      LazyInit Performance Benchmark v#{VERSION}
      ===================================================================
      Ruby: #{RUBY_VERSION} (#{RUBY_ENGINE})
      Platform: #{RUBY_PLATFORM}
      Time: #{Time.now}
      ===================================================================
    HEADER
  end

  def benchmark_comparison(category, test_name, manual_impl, lazy_impl, warmup: true)
    puts "\n--- #{test_name} ---"

    # Warmup if requested
    if warmup
      manual_impl.call
      lazy_impl.call
    end

    # Run benchmark
    suite = Benchmark.ips do |x|
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
    puts "\n" + '=' * 60
    puts '1. BASIC LAZY INITIALIZATION PATTERNS'
    puts '=' * 60

    # Hot path performance
    manual_basic = create_manual_basic
    lazy_basic = create_lazy_basic

    benchmark_comparison(
      'Basic Patterns',
      'Hot Path (after initialization)',
      -> { manual_basic.expensive_value },
      -> { lazy_basic.expensive_value }
    )

    # Cold start performance
    benchmark_comparison(
      'Basic Patterns',
      'Cold Start (new instances)',
      -> { create_manual_basic.expensive_value },
      -> { create_lazy_basic.expensive_value },
      warmup: false
    )
  end

  def run_computational_complexity
    puts "\n" + '=' * 60
    puts '2. COMPUTATIONAL COMPLEXITY SCENARIOS'
    puts '=' * 60

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
    puts "\n" + '=' * 60
    puts '3. DEPENDENCY INJECTION PERFORMANCE'
    puts '=' * 60

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
  end

  def run_class_level_shared
    puts "\n" + '=' * 60
    puts '5. CLASS-LEVEL SHARED RESOURCES'
    puts '=' * 60

    manual_class = create_manual_class_var
    lazy_class = create_lazy_class_var

    benchmark_comparison(
      'Class-Level Resources',
      'Shared Resources',
      -> { manual_class.shared_resource },
      -> { lazy_class.shared_resource }
    )
  end

  def run_method_memoization
    puts "\n" + '=' * 60
    puts '6. METHOD-LOCAL MEMOIZATION'
    puts '=' * 60

    manual_memo = create_manual_memo
    lazy_memo = create_lazy_memo

    benchmark_comparison(
      'Method Memoization',
      'Hot Path Memoization',
      -> { manual_memo.expensive_calc(100) },
      -> { lazy_memo.expensive_calc(100) }
    )
  end

  def run_timeout_overhead
    puts "\n" + '=' * 60
    puts '7. TIMEOUT OVERHEAD'
    puts '=' * 60

    no_timeout = create_no_timeout
    with_timeout = create_with_timeout

    benchmark_comparison(
      'Timeout Support',
      'Timeout vs No Timeout',
      -> { no_timeout.quick_operation },
      -> { with_timeout.quick_operation }
    )
  end

  def run_exception_handling
    puts "\n" + '=' * 60
    puts '8. EXCEPTION HANDLING OVERHEAD'
    puts '=' * 60

    manual_exception = create_manual_exception
    lazy_exception = create_lazy_exception

    benchmark_comparison(
      'Exception Handling',
      'Exception Recovery',
      -> { manual_exception.failing_method },
      -> { lazy_exception.failing_method }
    )
  end

  def run_real_world_scenarios
    puts "\n" + '=' * 60
    puts '9. REAL-WORLD SCENARIOS'
    puts '=' * 60

    manual_webapp = create_manual_webapp
    lazy_webapp = create_lazy_webapp

    benchmark_comparison(
      'Real-World',
      'Web Application Stack',
      -> { manual_webapp.application },
      -> { lazy_webapp.application }
    )
  end

  # ========================================
  # FACTORY METHODS
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

  def create_manual_conditional(enabled)
    Class.new do
      attr_accessor :feature_enabled

      def initialize(enabled)
        @feature_enabled = enabled
      end

      def feature
        return nil unless feature_enabled

        @feature ||= 'Feature loaded'
      end
    end.new(enabled)
  end

  # def create_lazy_conditional(enabled)
  #   Class.new do
  #     extend LazyInit
  #     attr_accessor :feature_enabled

  #     def initialize(enabled)
  #       @feature_enabled = enabled
  #     end

  #     lazy_attr_reader :feature, if_condition: -> { feature_enabled } do
  #       "Feature loaded"
  #     end
  #   end.new(enabled)
  # end

  def create_manual_class_var
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
    klass = Class.new do
      extend LazyInit

      lazy_class_variable :shared_resource do
        "Shared resource #{rand(1000)}"
      end
    end

    # Initialize the class variable
    klass.shared_resource
    klass.new
  end

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

      def expensive_calc(key)
        lazy_once { "computed_#{key}_#{rand(1000)}" }
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

  # ========================================
  # RESULTS & SUMMARY
  # ========================================

  def print_summary
    puts "\n" + '=' * 80
    puts 'BENCHMARK SUMMARY'
    puts '=' * 80

    print_detailed_results
    print_performance_analysis
    print_recommendations
  end

  def print_detailed_results
    puts "\nDetailed Results:"
    puts '-' * 50

    @results.each do |category, tests|
      puts "\n#{category}:"

      tests.each do |test_name, data|
        overhead_str = if data[:overhead_percent] < -50
                         "#{(-data[:overhead_percent]).round(1)}% faster"
                       elsif data[:overhead_percent] > 0
                         "#{data[:ratio]}x slower"
                       else
                         'similar performance'
                       end

        puts "  #{test_name}:"
        puts "    Manual:   #{format_ips(data[:manual])}"
        puts "    LazyInit: #{format_ips(data[:lazy_init])}"
        puts "    Result:   #{overhead_str}"
      end
    end
  end

  def print_performance_analysis
    puts "\n" + '=' * 50
    puts 'PERFORMANCE ANALYSIS'
    puts '=' * 50

    all_ratios = @results.values.flat_map(&:values).map { |data| data[:ratio] }
    avg_ratio = (all_ratios.sum / all_ratios.size).round(2)
    min_ratio = all_ratios.min.round(2)
    max_ratio = all_ratios.max.round(2)

    puts "\nOverall Performance Impact:"
    puts "  Average slowdown: #{avg_ratio}x"
    puts "  Best case: #{min_ratio}x slower"
    puts "  Worst case: #{max_ratio}x slower"

    # Analyze patterns
    computational = @results['Computational Complexity']
    if computational
      light_ratio = computational['Lightweight (sum 1..10)'][:ratio]
      heavy_ratio = computational['Heavy (filter+sqrt 1..10000)'][:ratio]

      if light_ratio > heavy_ratio * 1.5
        puts "\n• LazyInit overhead decreases with computation complexity"
        puts '• Better suited for expensive operations'
      else
        puts "\n• LazyInit overhead is consistent across complexity levels"
      end
    end

    conditional = @results['Conditional Loading']
    return unless conditional

    true_ratio = conditional['Condition True'][:ratio]
    false_ratio = conditional['Condition False'][:ratio]

    return unless false_ratio < true_ratio * 0.7

    puts '• Conditional loading is efficient when conditions are false'
  end

  def print_recommendations
    puts "\n" + '=' * 50
    puts 'RECOMMENDATIONS'
    puts '=' * 50

    all_ratios = @results.values.flat_map(&:values).map { |data| data[:ratio] }
    avg_ratio = all_ratios.sum / all_ratios.size

    puts "\nWhen to use LazyInit:"
    if avg_ratio > 10
      puts '• Only for very expensive initialization (>10ms)'
      puts '• When thread safety is critical'
      puts '• Complex dependency chains'
    elsif avg_ratio > 5
      puts '• Expensive initialization (>1ms)'
      puts '• Multi-threaded applications'
      puts '• When manual synchronization is error-prone'
    else
      puts '• Most lazy initialization scenarios'
      puts '• Thread-safe applications'
      puts '• Clean dependency management needed'
    end

    puts "\n" + '=' * 80
    puts 'BENCHMARK COMPLETED'
    puts '=' * 80
  end
end

# Run the benchmark
if __FILE__ == $0
  begin
    benchmark = LazyInitBenchmark.new
    benchmark.run_all
  rescue StandardError => e
    puts "Benchmark failed: #{e.message}"
    puts e.backtrace.first(5)
    exit 1
  end
end
