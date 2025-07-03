#!/usr/bin/env ruby
# frozen_string_literal: true

require 'benchmark/ips'
require_relative '../lib/lazy_init'

puts '=== DOGŁĘBNA ANALIZA BOTTLENECKÓW LAZYINIT ==='
puts "Ruby version: #{RUBY_VERSION}"

# === STEP 1: MICRO-BENCHMARK OF EACH ELEMENT ===

def micro_benchmark(description, &block)
  puts "\n--- #{description} ---"

  result = Benchmark.ips { |x| x.report('test', &block) }.entries.first.ips
  puts "  #{description}: #{format_ips(result)}"
  result
end

def format_ips(ips)
  if ips >= 1_000_000
    "#{(ips / 1_000_000.0).round(2)}M i/s"
  elsif ips >= 1_000
    "#{(ips / 1_000.0).round(1)}K i/s"
  else
    "#{ips.round(0)} i/s"
  end
end

puts "\n" + '=' * 80
puts 'STEP 1: ISOLATING INDIVIDUAL COMPONENTS'
puts '=' * 80

# 1.1 Direct instance variable access (baseline)
class DirectVar
  def initialize
    @value = 'computed_value'
  end

  def get_value
    @value
  end
end

direct = DirectVar.new
baseline = micro_benchmark('1.1 Direct @value access') { direct.get_value }

# 1.2 Manual ||= pattern
class ManualPattern
  def get_value
    @value ||= 'computed_value'
  end
end

manual = ManualPattern.new
manual.get_value # warm up
manual_result = micro_benchmark('1.2 Manual @value ||= (warm)') { manual.get_value }

# 1.3 LazyValue object access (isolated)
lazy_value = LazyInit::LazyValue.new { 'computed_value' }
lazy_value.value # warm up
lazy_value_result = micro_benchmark('1.3 LazyValue.value (warm)') { lazy_value.value }

# 1.4 Method dispatch przez generated method
class GeneratedMethodTest
  extend LazyInit
  lazy_attr_reader :test_value do
    'computed_value'
  end
end

generated = GeneratedMethodTest.new
generated.test_value # warm up
generated_result = micro_benchmark('1.4 Generated method (warm)') { generated.test_value }

puts "\n" + '=' * 50
puts 'STEP 1 ANALYSIS:'
puts '=' * 50
puts "Baseline (direct @var):     #{format_ips(baseline)}"
puts "Manual ||=:                 #{format_ips(manual_result)} (#{(baseline / manual_result).round(2)}x slower)"
puts "LazyValue only:             #{format_ips(lazy_value_result)} (#{(baseline / lazy_value_result).round(2)}x slower)"
puts "Generated method:           #{format_ips(generated_result)} (#{(baseline / generated_result).round(2)}x slower)"

# === STEP 2: DECOMPOSITION OF GENERATED METHOD ===

puts "\n" + '=' * 80
puts 'STEP 2: DECOMPOSITION GENERATED METHOD CALL'
puts '=' * 80

class DecompositionTest
  extend LazyInit

  lazy_attr_reader :full_method do
    'computed_value'
  end

  def initialize
    @manual_lazy_value = LazyInit::LazyValue.new { 'computed_value' }
    @manual_lazy_value.value # warm up
  end

  def step1_config_lookup
    self.class.lazy_initializers[:full_method]
  end

  def step2_dependency_check
    config = self.class.lazy_initializers[:full_method]
    config[:depends_on] # nil in this case
  end

  def step3_ivar_access
    instance_variable_get(:@full_method_lazy_value)
  end

  def step4_lazy_value_call
    @manual_lazy_value.value
  end

  def step5_full_manual_replication
    config = self.class.lazy_initializers[:full_method]

    # Skip dependency resolution if no dependencies
    # if config[:depends_on]
    #   self.class.dependency_resolver.resolve_dependencies(name, self)
    # end

    ivar_name = :@full_method_lazy_value
    lazy_value = instance_variable_get(ivar_name)

    unless lazy_value
      lazy_value = LazyInit::LazyValue.new(timeout: config[:timeout]) do
        instance_eval(&config[:block])
      end
      instance_variable_set(ivar_name, lazy_value)
    end

    lazy_value.value
  end
end

decomp = DecompositionTest.new
decomp.full_method # warm up

step1 = micro_benchmark('2.1 Config hash lookup') { decomp.step1_config_lookup }
step2 = micro_benchmark('2.2 Dependency check') { decomp.step2_dependency_check }
step3 = micro_benchmark('2.3 Instance var get') { decomp.step3_ivar_access }
step4 = micro_benchmark('2.4 LazyValue.value call') { decomp.step4_lazy_value_call }
step5 = micro_benchmark('2.5 Full manual replication') { decomp.step5_full_manual_replication }
full_method = micro_benchmark('2.6 Actual generated method') { decomp.full_method }

puts "\n" + '=' * 50
puts 'STEP 2 ANALYSIS:'
puts '=' * 50
puts "Config lookup:              #{format_ips(step1)} (#{(baseline / step1).round(2)}x slower than baseline)"
puts "Dependency check:           #{format_ips(step2)} (#{(baseline / step2).round(2)}x slower than baseline)"
puts "Instance var get:           #{format_ips(step3)} (#{(baseline / step3).round(2)}x slower than baseline)"
puts "LazyValue.value:            #{format_ips(step4)} (#{(baseline / step4).round(2)}x slower than baseline)"
puts "Manual replication:         #{format_ips(step5)} (#{(baseline / step5).round(2)}x slower than baseline)"
puts "Generated method:           #{format_ips(full_method)} (#{(baseline / full_method).round(2)}x slower than baseline)"

# === STEP 3: LAZYVALUE INTERNAL BOTTLENECKS ===

puts "\n" + '=' * 80
puts 'STEP 3: LAZYVALUE INTERNAL ANALYSIS'
puts '=' * 80

# Analiza LazyValue.value method
class LazyValueAnalysis
  def initialize
    @computed = true
    @value = 'computed_value'
    @mutex = Mutex.new
  end

  # Obecna implementacja (uproszczona)
  def current_implementation
    @mutex.synchronize do
      return @value if @computed
      # compute...
    end
  end

  # Fast path with double-checked locking
  def fast_path_implementation
    return @value if @computed

    @mutex.synchronize do
      return @value if @computed
      # compute...
    end
  end

  # Ultra fast path (tylko check)
  def ultra_fast_path
    return @value if @computed
  end

  # Mutex overhead test
  def mutex_overhead_test
    @mutex.synchronize do
      @value
    end
  end
end

lazy_analysis = LazyValueAnalysis.new

current = micro_benchmark('3.1 Current LazyValue impl') { lazy_analysis.current_implementation }
fast_path = micro_benchmark('3.2 Fast path impl') { lazy_analysis.fast_path_implementation }
ultra_fast = micro_benchmark('3.3 Ultra fast (just check)') { lazy_analysis.ultra_fast_path }
mutex_overhead = micro_benchmark('3.4 Mutex overhead') { lazy_analysis.mutex_overhead_test }

puts "\n" + '=' * 50
puts 'STEP 3 ANALYSIS:'
puts '=' * 50
puts "Current (always mutex):     #{format_ips(current)} (#{(baseline / current).round(2)}x slower than baseline)"
puts "Fast path (skip mutex):     #{format_ips(fast_path)} (#{(baseline / fast_path).round(2)}x slower than baseline)"
puts "Ultra fast (just check):    #{format_ips(ultra_fast)} (#{(baseline / ultra_fast).round(2)}x slower than baseline)"
puts "Mutex overhead:             #{format_ips(mutex_overhead)} (#{(baseline / mutex_overhead).round(2)}x slower than baseline)"

# === STEP 4: OPTIMIZED IMPLEMENTATIONS ===

puts "\n" + '=' * 80
puts 'STEP 4: OPTIMIZED IMPLEMENTATION PROTOTYPES'
puts '=' * 80

# Prototype 1: Cached config approach
class CachedConfigApproach
  extend LazyInit

  def self.lazy_attr_reader_optimized(name, &block)
    config = { block: block, timeout: nil, depends_on: nil }

    # Cache config in class for fast access
    ivar_name = "@#{name}_lazy_value"

    define_method(name) do
      lazy_value = instance_variable_get(ivar_name)

      unless lazy_value
        lazy_value = LazyInit::LazyValue.new(&config[:block])
        instance_variable_set(ivar_name, lazy_value)
      end

      lazy_value.value
    end
  end

  lazy_attr_reader_optimized :optimized_value do
    'computed_value'
  end
end

cached_config = CachedConfigApproach.new
cached_config.optimized_value # warm up
cached_result = micro_benchmark('4.1 Cached config approach') { cached_config.optimized_value }

# Prototype 2: Inline fast path
class InlineFastPath
  def initialize
    @value = 'computed_value'
    @computed = true
  end

  def inline_optimized
    # Inline the most common path
    return @value if @computed

    # Fallback to slow path (would be method call)
    slow_path_computation
  end

  def slow_path_computation
    # This would be the full LazyValue logic
    @value
  end
end

inline_test = InlineFastPath.new
inline_result = micro_benchmark('4.2 Inline fast path') { inline_test.inline_optimized }

# Prototype 3: Specialized generated methods
class SpecializedGenerated
  def initialize
    @test_value = 'computed_value'
    @test_value_computed = true
  end

  # This simulates a highly optimized generated method
  def specialized_test_value
    return @test_value if @test_value_computed

    # Slow path would go here
    @test_value
  end
end

specialized = SpecializedGenerated.new
specialized_result = micro_benchmark('4.3 Specialized generated') { specialized.specialized_test_value }

puts "\n" + '=' * 50
puts 'STEP 4 ANALYSIS:'
puts '=' * 50
puts "Cached config:              #{format_ips(cached_result)} (#{(baseline / cached_result).round(2)}x slower than baseline)"
puts "Inline fast path:           #{format_ips(inline_result)} (#{(baseline / inline_result).round(2)}x slower than baseline)"
puts "Specialized generated:      #{format_ips(specialized_result)} (#{(baseline / specialized_result).round(2)}x slower than baseline)"

# === STEP 5: FINAL COMPARISON ===

puts "\n" + '=' * 80
puts 'COMPREHENSIVE BOTTLENECK ANALYSIS'
puts '=' * 80

puts "\nBASELINE COMPARISON:"
puts "Direct @var access:         #{format_ips(baseline)} (1.0x - baseline)"
puts "Manual ||=:                 #{format_ips(manual_result)} (#{(baseline / manual_result).round(2)}x slower)"
puts ''
puts 'CURRENT LAZYINIT:'
puts "Generated method:           #{format_ips(generated_result)} (#{(baseline / generated_result).round(2)}x slower)"
puts ''
puts 'COMPONENT BREAKDOWN:'
puts "Config lookup:              #{format_ips(step1)} (#{(baseline / step1).round(2)}x slower)"
puts "LazyValue.value:            #{format_ips(step4)} (#{(baseline / step4).round(2)}x slower)"
puts "Mutex (always sync):        #{format_ips(current)} (#{(baseline / current).round(2)}x slower)"
puts ''
puts 'OPTIMIZATION POTENTIAL:'
puts "Fast path LazyValue:        #{format_ips(fast_path)} (#{(baseline / fast_path).round(2)}x slower)"
puts "Ultra fast path:            #{format_ips(ultra_fast)} (#{(baseline / ultra_fast).round(2)}x slower)"
puts "Inline optimization:        #{format_ips(inline_result)} (#{(baseline / inline_result).round(2)}x slower)"
puts "Specialized method:         #{format_ips(specialized_result)} (#{(baseline / specialized_result).round(2)}x slower)"

# === IDENTIFIED BOTTLENECKS ===

puts "\n" + '=' * 80
puts 'IDENTIFIED BOTTLENECKS (RANKED BY IMPACT)'
puts '=' * 80

bottlenecks = [
  {
    name: 'Config Hash Lookup',
    impact: baseline / step1,
    description: 'lazy_initializers[name] lookup w każdym call',
    fix: 'Cache config at method generation time'
  },
  {
    name: 'Mutex Synchronization',
    impact: baseline / current,
    description: 'Always synchronize, even for computed values',
    fix: 'Fast path with double-checked locking'
  },
  {
    name: 'LazyValue Object Overhead',
    impact: baseline / step4,
    description: 'Extra object layer adds method dispatch cost',
    fix: 'Inline critical path in generated methods'
  },
  {
    name: 'Instance Variable Access Pattern',
    impact: baseline / step3,
    description: 'instance_variable_get instead of direct @var',
    fix: 'Use direct @var access in generated methods'
  }
]

bottlenecks.sort_by { |b| -b[:impact] }.each_with_index do |bottleneck, i|
  puts "\n#{i + 1}. #{bottleneck[:name]} (#{bottleneck[:impact].round(2)}x impact)"
  puts "   Problem: #{bottleneck[:description]}"
  puts "   Fix: #{bottleneck[:fix]}"
end

theoretical_optimized = baseline / 1.5  # Theoretical 1.5x slower than baseline
current_gap = baseline / generated_result

puts "\nPERFORMANCE TARGETS:"
puts "Current performance:        #{format_ips(generated_result)} (#{current_gap.round(2)}x slower than baseline)"
puts "Realistic target:           #{format_ips(theoretical_optimized)} (1.5x slower than baseline)"
puts "Improvement needed:         #{(generated_result / theoretical_optimized).round(2)}x faster"

puts "\n" + '=' * 80
puts 'ANALYSIS COMPLETED'
puts '=' * 80
