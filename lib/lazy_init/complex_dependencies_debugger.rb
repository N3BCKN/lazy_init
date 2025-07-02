# frozen_string_literal: true

# COMPLEX DEPENDENCIES DEEP ANALYSIS DEBUGGER
# Goal: Find exact bottlenecks in complex dependencies (30.46x slower)
# 
# Current Status: Complex Dependencies 482.8K i/s vs Manual 14.71M i/s = 30.46x slower
# Target: Reduce to 8-12x slower (1.2-1.8M i/s)
# 
# Need to identify: Where exactly is the 30x overhead coming from?

module LazyInit
  class ComplexDependenciesDebugger
    def self.run_comprehensive_analysis
      puts "🔍 COMPLEX DEPENDENCIES COMPREHENSIVE ANALYSIS"
      puts "=" * 70
      
      analyze_lazyvalue_performance
      analyze_dependency_resolution_overhead  
      analyze_method_generation_complexity
      analyze_instance_computed_performance
      compare_simple_vs_complex_breakdown
      
      puts "\n" + "=" * 70
      puts "🎯 ANALYSIS COMPLETE - Check findings above"
    end

    def self.analyze_lazyvalue_performance
      puts "\n📊 LAZYVALUE PERFORMANCE DEEP DIVE"
      puts "-" * 50
      
      # Test LazyValue performance in isolation
      iterations = 1_000_000
      
      # Test 1: LazyValue creation cost
      creation_times = []
      10.times do
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        iterations.times { LazyInit::LazyValue.new { 'test' } }
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        creation_times << (end_time - start_time) / iterations * 1_000_000
      end
      avg_creation = creation_times.sum / creation_times.size
      
      # Test 2: LazyValue first access (computation)
      lazy_value = LazyInit::LazyValue.new { 'computed_value' }
      first_access_times = []
      10.times do
        lv = LazyInit::LazyValue.new { 'test_value' }
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        lv.value
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        first_access_times << (end_time - start_time) * 1_000_000
      end
      avg_first_access = first_access_times.sum / first_access_times.size
      
      # Test 3: LazyValue cached access (hot path)
      lazy_value.value # Initialize
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      iterations.times { lazy_value.value }
      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      cached_access_time = (end_time - start_time) / iterations * 1_000_000
      
      puts "LazyValue creation: #{avg_creation.round(3)}μs per instance"
      puts "LazyValue first access: #{avg_first_access.round(3)}μs per call"  
      puts "LazyValue cached access: #{cached_access_time.round(3)}μs per call"
      puts "Total LazyValue overhead: #{(avg_creation + cached_access_time).round(3)}μs"
    end

    def self.analyze_dependency_resolution_overhead
      puts "\n📊 DEPENDENCY RESOLUTION OVERHEAD ANALYSIS"
      puts "-" * 50
      
      # Create test class with dependencies
      test_class = Class.new do
        extend LazyInit
        
        lazy_attr_reader :config do
          { value: 'test_config' }
        end
        
        lazy_attr_reader :service, depends_on: [:config] do
          "service_#{config[:value]}"
        end
      end
      
      instance = test_class.new
      resolver = test_class.dependency_resolver
      
      # Initialize dependencies first
      instance.config
      
      # Test isolated dependency resolution call
      iterations = 100_000
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      iterations.times do
        resolver.resolve_dependencies(:service, instance)
      end
      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      
      resolution_time = (end_time - start_time) / iterations * 1_000_000
      puts "Dependency resolution call: #{resolution_time.round(3)}μs per call"
      
      # Test instance_computed? method performance
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      iterations.times do
        resolver.send(:instance_computed?, instance, :config)
      end
      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      
      computed_check_time = (end_time - start_time) / iterations * 1_000_000
      puts "instance_computed? check: #{computed_check_time.round(3)}μs per call"
    end

    def self.analyze_method_generation_complexity
      puts "\n📊 METHOD GENERATION COMPLEXITY ANALYSIS" 
      puts "-" * 50
      
      # Compare generated method complexity
      simple_class = Class.new do
        extend LazyInit
        lazy_attr_reader :simple_attr do
          'simple'
        end
      end
      
      complex_class = Class.new do
        extend LazyInit
        lazy_attr_reader :config do
          { value: 'config' }
        end
        lazy_attr_reader :complex_attr, depends_on: [:config] do
          "complex_#{config[:value]}"
        end
      end
      
      simple_instance = simple_class.new
      complex_instance = complex_class.new
      
      # Initialize both
      simple_instance.simple_attr
      complex_instance.complex_attr
      
      # Benchmark method call overhead (hot path)
      iterations = 1_000_000
      
      # Simple method timing
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      iterations.times { simple_instance.simple_attr }
      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      simple_time = (end_time - start_time) / iterations * 1_000_000
      
      # Complex method timing  
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      iterations.times { complex_instance.complex_attr }
      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      complex_time = (end_time - start_time) / iterations * 1_000_000
      
      puts "Simple method call: #{simple_time.round(3)}μs per call"
      puts "Complex method call: #{complex_time.round(3)}μs per call"
      puts "Complex overhead: #{(complex_time / simple_time).round(2)}x slower than simple"
      
      # Analyze what adds the extra overhead
      overhead_breakdown = complex_time - simple_time
      puts "Extra overhead in complex: #{overhead_breakdown.round(3)}μs per call"
    end

    def self.analyze_instance_computed_performance
      puts "\n📊 INSTANCE_COMPUTED? PERFORMANCE DEEP DIVE"
      puts "-" * 50
      
      test_class = Class.new do
        extend LazyInit
        lazy_attr_reader :test_attr do
          'test_value'
        end
      end
      
      instance = test_class.new
      instance.test_attr # Initialize
      
      resolver = test_class.dependency_resolver
      iterations = 1_000_000
      
      # Test current instance_computed? implementation
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      iterations.times do
        resolver.send(:instance_computed?, instance, :test_attr)
      end
      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      current_time = (end_time - start_time) / iterations * 1_000_000
      
      # Test alternative: direct instance variable check
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      iterations.times do
        # Simulate what instance_computed? does internally
        lazy_value_var = "@test_attr_lazy_value"
        if instance.instance_variable_defined?(lazy_value_var)
          lazy_value = instance.instance_variable_get(lazy_value_var)
          lazy_value && lazy_value.computed?
        else
          false
        end
      end
      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      direct_time = (end_time - start_time) / iterations * 1_000_000
      
      # Test even more direct approach
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      iterations.times do
        # Just check if lazy value exists and is computed
        lazy_value = instance.instance_variable_get("@test_attr_lazy_value")
        lazy_value&.computed?
      end
      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      ultra_direct_time = (end_time - start_time) / iterations * 1_000_000
      
      puts "Current instance_computed?: #{current_time.round(3)}μs per call"
      puts "Direct variable access: #{direct_time.round(3)}μs per call"  
      puts "Ultra-direct access: #{ultra_direct_time.round(3)}μs per call"
      puts "Optimization potential: #{(current_time / ultra_direct_time).round(2)}x faster possible"
    end

    def self.compare_simple_vs_complex_breakdown
      puts "\n📊 SIMPLE VS COMPLEX EXECUTION BREAKDOWN"
      puts "-" * 50
      
      # Create comparable simple and complex scenarios
      simple_class = Class.new do
        extend LazyInit
        lazy_attr_reader :value do
          'simple_value'
        end
      end
      
      complex_class = Class.new do
        extend LazyInit
        lazy_attr_reader :config do
          { key: 'config_value' }
        end
        lazy_attr_reader :value, depends_on: [:config] do
          "complex_#{config[:key]}"
        end
      end
      
      manual_class = Class.new do
        def config
          @config ||= { key: 'config_value' }
        end
        
        def value
          @value ||= "complex_#{config[:key]}"
        end
      end
      
      # Initialize instances
      simple_instance = simple_class.new
      complex_instance = complex_class.new  
      manual_instance = manual_class.new
      
      # Warm up
      simple_instance.value
      complex_instance.value
      manual_instance.value
      
      # Benchmark each approach
      iterations = 1_000_000
      
      benchmarks = [
        ['Manual ||=', manual_instance, :value],
        ['Simple LazyInit', simple_instance, :value],
        ['Complex LazyInit', complex_instance, :value]
      ]
      
      results = {}
      benchmarks.each do |name, instance, method|
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        iterations.times { instance.send(method) }
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        
        time_per_op = (end_time - start_time) / iterations * 1_000_000
        results[name] = time_per_op
        puts "#{name}: #{time_per_op.round(3)}μs per operation"
      end
      
      # Calculate overhead breakdown
      manual_time = results['Manual ||=']
      simple_time = results['Simple LazyInit']
      complex_time = results['Complex LazyInit']
      
      simple_overhead = simple_time - manual_time
      complex_overhead = complex_time - manual_time
      additional_complex_overhead = complex_time - simple_time
      
      puts "\nOVERHEAD BREAKDOWN:"
      puts "Manual baseline: #{manual_time.round(3)}μs"
      puts "Simple overhead: +#{simple_overhead.round(3)}μs (#{(simple_time/manual_time).round(2)}x total)"
      puts "Complex total overhead: +#{complex_overhead.round(3)}μs (#{(complex_time/manual_time).round(2)}x total)"
      puts "Additional complex overhead: +#{additional_complex_overhead.round(3)}μs"
      puts "Complex vs Simple: #{(complex_time/simple_time).round(2)}x slower"
    end

    def self.profile_real_world_scenario
      puts "\n📊 REAL-WORLD SCENARIO PROFILING"
      puts "-" * 50
      
      # Recreate the web application scenario from benchmarks
      real_world_class = Class.new do
        extend LazyInit
        
        lazy_attr_reader :config do
          { 
            database_url: 'postgresql://localhost/app',
            api_url: 'https://api.example.com',
            cache_enabled: true
          }
        end
        
        lazy_attr_reader :database, depends_on: [:config] do
          "Database connection to #{config[:database_url]}"
        end
        
        lazy_attr_reader :cache, depends_on: [:config] do
          config[:cache_enabled] ? "Redis cache enabled" : nil
        end
        
        lazy_attr_reader :api_client, depends_on: [:config] do
          "API client for #{config[:api_url]}"
        end
        
        lazy_attr_reader :application, depends_on: [:database, :cache, :api_client] do
          "App with #{database}, #{cache}, #{api_client}"
        end
      end
      
      instance = real_world_class.new
      
      # Profile step-by-step initialization
      puts "Profiling real-world initialization:"
      
      attributes = [:config, :database, :cache, :api_client, :application]
      attributes.each do |attr|
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = instance.send(attr)
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        
        init_time = (end_time - start_time) * 1_000_000
        puts "  #{attr}: #{init_time.round(3)}μs (first access)"
      end
      
      # Profile hot path performance
      puts "\nProfiling real-world hot path:"
      iterations = 100_000
      
      attributes.each do |attr|
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        iterations.times { instance.send(attr) }
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        
        hot_path_time = (end_time - start_time) / iterations * 1_000_000
        puts "  #{attr}: #{hot_path_time.round(3)}μs per call (hot path)"
      end
    end
  end
end

# USAGE:
# LazyInit::ComplexDependenciesDebugger.run_comprehensive_analysis
#
# EXPECTED FINDINGS:
# 1. LazyValue overhead breakdown (creation vs access)
# 2. Dependency resolution bottlenecks  
# 3. instance_computed? performance issues
# 4. Method generation complexity overhead
# 5. Real-world scenario bottleneck identification
#
# KEY QUESTIONS TO ANSWER:
# - Is LazyValue cached access really just 0.12μs or higher in complex scenarios?
# - How much overhead does dependency resolution add per call?
# - Is instance_computed? the main bottleneck in resolution?
# - What's the exact breakdown of 30x overhead in complex dependencies?
# - Which specific component needs optimization most?