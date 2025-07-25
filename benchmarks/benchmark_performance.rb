require 'benchmark'
require_relative '../lib/lazy_init.rb'

module ExpensiveOperations
  def parse_configuration
    config_data = {
      database: {
        host: 'localhost',
        port: 5432,
        pool_size: 20,
        timeout: 30,
        retries: 3
      },
      redis: {
        url: 'redis://localhost:6379',
        pool_size: 10,
        timeout: 5
      },
      api_keys: Hash[(1..50).map { |i| ["key_#{i}", "secret_#{rand(100000)}"] }],
      feature_flags: Hash[(1..100).map { |i| ["feature_#{i}", [true, false].sample] }]
    }
    
    serialized = config_data.to_s
    100.times { serialized.gsub(/\d+/, &:to_i) }
    
    config_data
  end
  
  def generate_secure_token
    require 'digest'
    
    base_string = "secure_token_#{Time.now.to_f}_#{rand(1000000)}"
    
    token = base_string
    1000.times do |i|
      token = Digest::SHA256.hexdigest("#{token}_#{i}")
    end
    
    token
  end
  
  def process_dataset
    data = (1..1000).map do |i|
      {
        id: i,
        timestamp: Time.now - rand(86400 * 30),
        value: rand(1000.0).round(2),
        category: ['A', 'B', 'C', 'D'][rand(4)],
        metadata: { source: "system_#{rand(10)}", priority: rand(5) }
      }
    end
    
    grouped = data.group_by { |item| item[:category] }
    aggregated = grouped.transform_values do |items|
      {
        count: items.size,
        total_value: items.sum { |item| item[:value] },
        avg_value: items.sum { |item| item[:value] } / items.size.to_f,
        latest: items.max_by { |item| item[:timestamp] }
      }
    end
    
    aggregated
  end
end

class ManualClass
  include ExpensiveOperations
  
  def configuration
    @configuration ||= parse_configuration
  end
  
  def secure_token
    @secure_token ||= generate_secure_token
  end
  
  def processed_data
    @processed_data ||= process_dataset
  end
end

class LazyClass
  extend LazyInit
  include ExpensiveOperations
  
  lazy_attr_reader :configuration do
    parse_configuration
  end
  
  lazy_attr_reader :secure_token do
    generate_secure_token
  end
  
  lazy_attr_reader :processed_data do
    process_dataset
  end
end

puts "LazyInit vs Manual Performance Benchmark"
puts "Testing with realistic production-like expensive operations:\n\n"

scenarios = [
  {
    name: "Configuration Parsing",
    method: :configuration,
    description: "JSON/YAML parsing with complex nested structures"
  },
  {
    name: "Cryptographic Operations", 
    method: :secure_token,
    description: "Secure token generation with multiple hash rounds"
  },
  {
    name: "Data Processing",
    method: :processed_data,
    description: "ETL-style data aggregation and grouping"
  }
]

scenarios.each do |scenario|
  puts "--- #{scenario[:name]} ---"
  puts "Description: #{scenario[:description]}\n\n"
  
  manual = ManualClass.new
  lazy = LazyClass.new
  
  puts "Warming up (performing actual expensive computation)..."
  manual_start = Time.now
  manual.send(scenario[:method])
  manual_time = Time.now - manual_start
  
  lazy_start = Time.now  
  lazy.send(scenario[:method])
  lazy_time = Time.now - lazy_start
  
  puts "Initial computation time:"
  puts "  Manual: #{(manual_time * 1000).round(2)}ms"
  puts "  LazyInit: #{(lazy_time * 1000).round(2)}ms"
  puts "  Difference: #{((lazy_time - manual_time) * 1000).round(2)}ms\n\n"
  
  puts "Benchmarking cached access (100,000 iterations):"
  Benchmark.bm(10) do |x|
    x.report("Manual") { 100_000.times { manual.send(scenario[:method]) } }
    x.report("LazyInit") { 100_000.times { lazy.send(scenario[:method]) } }
  end
  
  puts "\n" + "="*60 + "\n\n"
end

puts "Thread Safety Test"
puts "Testing concurrent access to verify no race conditions...\n"

class ThreadTestClass
  extend LazyInit
  include ExpensiveOperations
  
  lazy_attr_reader :thread_safe_data do
    puts "Computing in thread: #{Thread.current.object_id}"
    process_dataset
  end
end

service = ThreadTestClass.new

results = []
threads = 10.times.map do |i|
  Thread.new do
    data = service.thread_safe_data
    results << data.object_id
  end
end

threads.each(&:join)

puts "Thread safety results:"
puts "  Unique object IDs: #{results.uniq.size} (should be 1)"
puts "  All threads got same object: #{results.uniq.size == 1 ? '✅ PASS' : '❌ FAIL'}"
puts "  Total threads: #{results.size}"
puts "Test Environment: Ruby #{RUBY_VERSION}, #{RbConfig::CONFIG['target_cpu']}"
puts "Platform: #{RUBY_PLATFORM}"

if results.uniq.size == 1
  puts "\n Thread safety confirmed: All threads received the same computed object"
else
  puts "\n Thread safety failed: Race condition detected!"
end