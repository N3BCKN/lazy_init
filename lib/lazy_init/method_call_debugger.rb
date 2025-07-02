# frozen_string_literal: true

# METHOD CALL OVERHEAD DEBUGGER
# Goal: Find out why method calls take 31μs + 14μs instead of ~0.1μs
# 
# From debug results we know:
# - Method call time: 31μs + 14μs (should be ~0.1μs)
# - This is 100-300x too slow
# - Need to find what's causing this overhead

module LazyInit
  class MethodCallDebugger
    def self.investigate_simple_vs_complex_usage
      puts "🔍 INVESTIGATING SIMPLE VS COMPLEX IMPLEMENTATION USAGE"
      puts "=" * 60
      
      # Test different attribute types
      test_class = Class.new do
        extend LazyInit
        
        # Should use SIMPLE implementation (no deps, no timeout, no condition)
        lazy_attr_reader :simple_attr do
          'simple_value'
        end
        
        # Should use COMPLEX implementation (has dependencies)
        lazy_attr_reader :config do
          { value: 'config' }
        end
        
        lazy_attr_reader :dependent_attr, depends_on: [:config] do
          "dependent_#{config[:value]}"
        end
        
        # Should use COMPLEX implementation (has timeout)
        lazy_attr_reader :timeout_attr, timeout: 5 do
          'timeout_value'
        end
        
        # Should use COMPLEX implementation (has condition)
        lazy_attr_reader :conditional_attr, if_condition: -> { true } do
          'conditional_value'
        end
      end
      
      instance = test_class.new
      
      # Initialize all attributes
      attributes = [:simple_attr, :dependent_attr, :timeout_attr, :conditional_attr]
      attributes.each { |attr| instance.send(attr) }
      
      puts "IMPLEMENTATION TYPE DETECTION:"
      attributes.each do |attr|
        # Check for simple implementation variables
        simple_computed = "@#{attr}_computed"
        simple_value = "@#{attr}_value"
        simple_mutex = "@#{attr}_mutex"
        simple_exception = "@#{attr}_exception"
        
        # Check for complex implementation variables
        complex_lazy_value = "@#{attr}_lazy_value"
        
        has_simple_vars = [simple_computed, simple_value, simple_mutex, simple_exception].any? do |var|
          instance.instance_variable_defined?(var)
        end
        
        has_complex_vars = instance.instance_variable_defined?(complex_lazy_value)
        
        implementation_type = if has_simple_vars && !has_complex_vars
          "SIMPLE (inline variables)"
        elsif has_complex_vars && !has_simple_vars
          "COMPLEX (LazyValue wrapper)"
        elsif has_simple_vars && has_complex_vars
          "MIXED (both implementations - BUG!)"
        else
          "UNKNOWN (no variables found)"
        end
        
        puts "  #{attr}: #{implementation_type}"
        
        if has_simple_vars
          simple_vars = [simple_computed, simple_value, simple_mutex, simple_exception].select do |var|
            instance.instance_variable_defined?(var)
          end
          puts "    Simple vars: #{simple_vars}"
        end
        
        if has_complex_vars
          puts "    Complex vars: [#{complex_lazy_value}]"
        end
      end
    end

    def self.debug_simple_case_detection
      puts "\n🔍 DEBUGGING SIMPLE CASE DETECTION LOGIC"
      puts "=" * 60
      
      # Test the simple_case? method directly
      test_scenarios = [
        { name: "Pure simple", timeout: nil, depends_on: nil, if_condition: nil },
        { name: "Has timeout", timeout: 5, depends_on: nil, if_condition: nil },
        { name: "Has dependencies", timeout: nil, depends_on: [:config], if_condition: nil },
        { name: "Has condition", timeout: nil, depends_on: nil, if_condition: -> { true } },
        { name: "Empty dependencies", timeout: nil, depends_on: [], if_condition: nil },
      ]
      
      # We need to access the simple_case? method - let's simulate it
      test_scenarios.each do |scenario|
        timeout = scenario[:timeout]
        depends_on = scenario[:depends_on]
        if_condition = scenario[:if_condition]
        
        # This should match the logic in ClassMethods.simple_case?
        is_simple = timeout.nil? && depends_on.nil? && if_condition.nil?
        
        puts "#{scenario[:name]}: #{is_simple ? 'SIMPLE' : 'COMPLEX'}"
        puts "  timeout: #{timeout.inspect}"
        puts "  depends_on: #{depends_on.inspect}"
        puts "  if_condition: #{if_condition.inspect}"
      end
    end

    def self.benchmark_method_execution_breakdown
      puts "\n🔍 METHOD EXECUTION TIMING BREAKDOWN"
      puts "=" * 60
      
      # Create test classes with different implementations
      simple_class = Class.new do
        extend LazyInit
        lazy_attr_reader :simple_attr do
          'simple_value'
        end
      end
      
      complex_class = Class.new do
        extend LazyInit
        lazy_attr_reader :config do
          { value: 'test' }
        end
        lazy_attr_reader :complex_attr, depends_on: [:config] do
          "complex_#{config[:value]}"
        end
      end
      
      # Manual comparison
      manual_class = Class.new do
        def manual_attr
          @manual_attr ||= 'manual_value'
        end
      end
      
      # Initialize instances
      simple_instance = simple_class.new
      complex_instance = complex_class.new
      manual_instance = manual_class.new
      
      # Warm up (compute values)
      simple_instance.simple_attr
      complex_instance.complex_attr
      manual_instance.manual_attr
      
      # Benchmark each type
      iterations = 1_000_000
      
      benchmarks = [
        ['Manual ||=', manual_instance, :manual_attr],
        ['Simple LazyInit', simple_instance, :simple_attr],
        ['Complex LazyInit', complex_instance, :complex_attr]
      ]
      
      benchmarks.each do |name, instance, method|
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        iterations.times { instance.send(method) }
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        
        duration = end_time - start_time
        ops_per_sec = iterations / duration
        time_per_op = (duration / iterations) * 1_000_000 # microseconds
        
        puts "#{name}:"
        puts "  #{ops_per_sec.round(0)} ops/sec"
        puts "  #{time_per_op.round(3)}μs per operation"
      end
    end

    def self.investigate_lazyvalue_overhead
      puts "\n🔍 INVESTIGATING LAZYVALUE OVERHEAD"
      puts "=" * 60
      
      # Test LazyValue creation and access overhead
      creation_times = []
      access_times = []
      
      100.times do
        # Time LazyValue creation
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        lazy_value = LazyInit::LazyValue.new { 'test_value' }
        creation_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
        creation_times << creation_time
        
        # Time first access (computation)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = lazy_value.value
        first_access_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
        
        # Time second access (cached)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = lazy_value.value
        cached_access_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
        
        access_times << cached_access_time
      end
      
      avg_creation = (creation_times.sum / creation_times.size) * 1_000_000
      avg_access = (access_times.sum / access_times.size) * 1_000_000
      
      puts "LazyValue creation average: #{avg_creation.round(3)}μs"
      puts "LazyValue cached access average: #{avg_access.round(3)}μs"
      puts "Total LazyValue overhead: #{(avg_creation + avg_access).round(3)}μs"
    end

    def self.profile_generated_method_calls
      puts "\n🔍 PROFILING GENERATED METHOD CALLS"
      puts "=" * 60
      
      test_class = Class.new do
        extend LazyInit
        
        # Simple case
        lazy_attr_reader :simple_test do
          'simple'
        end
        
        # Complex case
        lazy_attr_reader :config do
          { value: 'config' }
        end
        
        lazy_attr_reader :complex_test, depends_on: [:config] do
          "complex_#{config[:value]}"
        end
      end
      
      instance = test_class.new
      
      # Initialize
      instance.simple_test
      instance.complex_test
      
      # Profile different parts of method execution
      puts "Profiling simple_test method execution:"
      
      # Time the entire method call
      iterations = 100_000
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      iterations.times { instance.simple_test }
      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      
      simple_time_per_op = ((end_time - start_time) / iterations) * 1_000_000
      puts "  Full method call: #{simple_time_per_op.round(3)}μs"
      
      # Profile complex method
      puts "Profiling complex_test method execution:"
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      iterations.times { instance.complex_test }
      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      
      complex_time_per_op = ((end_time - start_time) / iterations) * 1_000_000
      puts "  Full method call: #{complex_time_per_op.round(3)}μs"
      
      overhead_ratio = complex_time_per_op / simple_time_per_op
      puts "  Complex vs Simple overhead: #{overhead_ratio.round(2)}x"
    end

    def self.run_full_investigation
      puts "🔍 METHOD CALL OVERHEAD INVESTIGATION"
      puts "=" * 80
      
      investigate_simple_vs_complex_usage
      debug_simple_case_detection
      benchmark_method_execution_breakdown
      investigate_lazyvalue_overhead
      profile_generated_method_calls
      
      puts "\n" + "=" * 80
      puts "🎯 INVESTIGATION COMPLETE"
      
      puts "\nKEY QUESTIONS TO ANSWER:"
      puts "1. Are simple attributes using SIMPLE implementation?"
      puts "2. Is simple_case detection working correctly?"
      puts "3. What's the overhead breakdown between LazyValue vs direct variables?"
      puts "4. Are there hidden costs in generated methods?"
    end
  end
end

# EXPECTED FINDINGS:
#
# POTENTIAL ISSUES WE'RE LOOKING FOR:
# 1. Simple case detection not working - all attributes use COMPLEX LazyValue
# 2. LazyValue overhead higher than expected
# 3. Generated methods have hidden complexity
# 4. Instance variable access is slower than expected
# 5. Dependency resolution still called for simple cases
#
# DEBUGGING STRATEGY:
# - Check which implementation type each attribute actually uses
# - Measure LazyValue creation + access overhead
# - Compare simple vs complex method execution times
# - Profile individual components of method calls
#
# USAGE: LazyInit::MethodCallDebugger.run_full_investigation