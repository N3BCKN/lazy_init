require 'lazy_init'
require 'benchmark'

#  ===  THREAD SAFETY TESTS ===
# Testing LazyInit in production-like concurrent scenarios

#  TEST 1: Traffic Spike Simulation
# Simulating 200 simultaneous user requests hitting cached resources
# ------------------------------------------------------------
# Starting traffic spike test...
#  Loading DB config in thread: 60
# Creating connection pool in thread: 60
# Fetching permissions in thread: 60

#  Traffic Spike Results:
#   Duration: 472.91ms
#   Threads: 200
#   Successful requests: 200
#   Errors: 0

#  Race Condition Analysis:
#   DB Config - Unique objects: 1 (should be 1)
#   Connection Pool - Unique objects: 1 (should be 1)
#   Permissions - Unique objects: 1 (should be 1)
#   Result: ✅ PASS - No race conditions detected

# ============================================================
# TEST 2: Sustained Load Simulation
# Simulating background workers with sustained concurrent access
# ------------------------------------------------------------
# Starting sustained load test (30 workers x 50 operations each)...
# Initializing API client in thread: 140
# Fetching permissions in thread: 140

#  Sustained Load Results:
#   Duration: 0.25s
#   Total operations: 1500
#   Errors: 0
#   Operations/second: 6039

#   Consistency Analysis:
#   API Client - Unique objects: 1 (should be 1)
#   Shared Cache - Unique objects: 1 (should be 1)
#   Result: ✅ PASS - Consistency maintained

# ============================================================
#  TEST 3: Dependency Chain Stress Test
# Testing complex dependency resolution under concurrent pressure
# ------------------------------------------------------------
# Starting dependency chain test (100 concurrent accesses to complex dependency)...
# Computing base_config in thread: 220
#  Loading DB config in thread: 220
# Computing connection_manager in thread: 220
# Creating connection pool in thread: 220
# Computing auth_service in thread: 220
# Fetching permissions in thread: 220
# Computing api_gateway in thread: 220
# Initializing API client in thread: 220

#  Dependency Chain Results:
#   Duration: 550.29ms
#   All dependencies computed: true
#   Unique gateway objects: 1 (should be 1)
#   Result: ✅ PASS - Dependency resolution works correctly

# ============================================================
# TEST 4: Reset and Recovery Under Load
# Testing reset operations during concurrent access (production maintenance scenario)
# ------------------------------------------------------------
# Starting reset test (readers + periodic resets)...
#  Loading DB config in thread: 260
#   Reset 1 performed
#   Reset 2 performed
#  Loading DB config in thread: 300
#   Reset 3 performed
#  Loading DB config in thread: 340
#   Reset 4 performed
#  Loading DB config in thread: 380
#   Reset 5 performed
#  Loading DB config in thread: 420
#   Reset 6 performed
#  Loading DB config in thread: 460
#   Reset 7 performed
#  Loading DB config in thread: 300
#   Reset 8 performed
#  Loading DB config in thread: 300

#  Reset and Recovery Results:
#   Total access attempts: 1000
#   Successful accesses: 1000
#   Resets performed: 8
#   Success rate: 100.0%
#   Unique config objects: 8 (should be > 1 due to resets)
#   Result: ✅ PASS - Reset and recovery works correctly

# ============================================================
#  === FINAL THREAD SAFETY SUMMARY ===
# Test Environment: Ruby 3.0.2, x86_64
# Platform: x86_64-darwin19

# Results:
#   ✅ Traffic Spike (200 concurrent): PASS
#   ✅ Sustained Load (1500 operations): PASS
#   ✅ Dependency Chain (100 concurrent): PASS
#   ✅ Reset Recovery (periodic resets): PASS

# Overall Result: ✅ ALL TESTS PASSED

module ProductionOperations
  def load_database_config
    puts " Loading DB config in thread: #{Thread.current.object_id}"
    sleep(0.1)
    {
      host: 'prod-db.company.com',
      port: 5432,
      pool_size: 20,
      connections: Array.new(20) { |i| "conn_#{i}_#{rand(10_000)}" }
    }
  end

  def create_connection_pool
    puts "Creating connection pool in thread: #{Thread.current.object_id}"
    sleep(0.2)
    pool_id = rand(100_000)
    {
      id: pool_id,
      connections: Array.new(50) { |i| "active_conn_#{pool_id}_#{i}" },
      created_at: Time.now
    }
  end

  def fetch_user_permissions
    puts "Fetching permissions in thread: #{Thread.current.object_id}"
    sleep(0.15)
    permissions = {}
    (1..1000).each { |i| permissions["user_#{i}"] = %w[read write admin].sample }
    permissions
  end

  def initialize_api_client
    puts "Initializing API client in thread: #{Thread.current.object_id}"
    sleep(0.08)
    {
      client_id: "api_#{rand(50_000)}",
      token: "bearer_#{rand(1_000_000)}",
      endpoints: %w[users orders payments analytics],
      initialized_at: Time.now
    }
  end
end

puts ' ===  THREAD SAFETY TESTS ==='
puts "Testing LazyInit in production-like concurrent scenarios\n\n"

puts ' TEST 1: Traffic Spike Simulation'
puts 'Simulating 200 simultaneous user requests hitting cached resources'
puts '-' * 60

class TrafficSpikeService
  extend LazyInit
  include ProductionOperations

  lazy_attr_reader :db_config do
    load_database_config
  end

  lazy_attr_reader :connection_pool do
    create_connection_pool
  end

  lazy_attr_reader :user_permissions do
    fetch_user_permissions
  end
end

spike_service = TrafficSpikeService.new
spike_results = []
spike_errors = []

puts 'Starting traffic spike test...'
start_time = Time.now

spike_threads = 200.times.map do |i|
  Thread.new do
    config = spike_service.db_config
    pool = spike_service.connection_pool
    permissions = spike_service.user_permissions

    spike_results << {
      thread: i,
      config_id: config.object_id,
      pool_id: pool.object_id,
      permissions_id: permissions.object_id,
      timestamp: Time.now
    }
  rescue StandardError => e
    spike_errors << { thread: i, error: e.message }
  end
end

spike_threads.each(&:join)
spike_duration = Time.now - start_time

puts "\n Traffic Spike Results:"
puts "  Duration: #{(spike_duration * 1000).round(2)}ms"
puts "  Threads: #{spike_threads.size}"
puts "  Successful requests: #{spike_results.size}"
puts "  Errors: #{spike_errors.size}"

config_ids = spike_results.map { |r| r[:config_id] }.uniq
pool_ids = spike_results.map { |r| r[:pool_id] }.uniq
permission_ids = spike_results.map { |r| r[:permissions_id] }.uniq

puts "\n Race Condition Analysis:"
puts "  DB Config - Unique objects: #{config_ids.size} (should be 1)"
puts "  Connection Pool - Unique objects: #{pool_ids.size} (should be 1)"
puts "  Permissions - Unique objects: #{permission_ids.size} (should be 1)"

spike_passed = config_ids.size == 1 && pool_ids.size == 1 && permission_ids.size == 1
puts "  Result: #{spike_passed ? '✅ PASS' : '❌ FAIL'} - No race conditions detected"

puts "\n" + '=' * 60 + "\n"

puts 'TEST 2: Sustained Load Simulation'
puts 'Simulating background workers with sustained concurrent access'
puts '-' * 60

class WorkerService
  extend LazyInit
  include ProductionOperations

  lazy_attr_reader :api_client do
    initialize_api_client
  end

  lazy_attr_reader :shared_cache do
    fetch_user_permissions
  end
end

worker_service = WorkerService.new
worker_results = []
worker_errors = []

puts 'Starting sustained load test (30 workers x 50 operations each)...'

worker_threads = 30.times.map do |worker_id|
  Thread.new do
    thread_results = []
    50.times do |operation|
      api = worker_service.api_client
      cache = worker_service.shared_cache

      thread_results << {
        worker: worker_id,
        operation: operation,
        api_id: api.object_id,
        cache_id: cache.object_id
      }

      sleep(0.001) if operation % 10 == 0
    rescue StandardError => e
      worker_errors << { worker: worker_id, operation: operation, error: e.message }
    end

    worker_results.concat(thread_results)
  end
end

worker_start = Time.now
worker_threads.each(&:join)
worker_duration = Time.now - worker_start

puts "\n Sustained Load Results:"
puts "  Duration: #{worker_duration.round(2)}s"
puts "  Total operations: #{worker_results.size}"
puts "  Errors: #{worker_errors.size}"
puts "  Operations/second: #{(worker_results.size / worker_duration).round(0)}"

api_ids = worker_results.map { |r| r[:api_id] }.uniq
cache_ids = worker_results.map { |r| r[:cache_id] }.uniq

puts "\n  Consistency Analysis:"
puts "  API Client - Unique objects: #{api_ids.size} (should be 1)"
puts "  Shared Cache - Unique objects: #{cache_ids.size} (should be 1)"

worker_passed = api_ids.size == 1 && cache_ids.size == 1
puts "  Result: #{worker_passed ? '✅ PASS' : '❌ FAIL'} - Consistency maintained"

puts "\n" + '=' * 60 + "\n"

puts ' TEST 3: Dependency Chain Stress Test'
puts 'Testing complex dependency resolution under concurrent pressure'
puts '-' * 60

class DependencyChainService
  extend LazyInit
  include ProductionOperations

  lazy_attr_reader :base_config do
    puts "Computing base_config in thread: #{Thread.current.object_id}"
    load_database_config
  end

  lazy_attr_reader :connection_manager, depends_on: [:base_config] do
    puts "Computing connection_manager in thread: #{Thread.current.object_id}"
    create_connection_pool
  end

  lazy_attr_reader :auth_service, depends_on: [:base_config] do
    puts "Computing auth_service in thread: #{Thread.current.object_id}"
    fetch_user_permissions
  end

  lazy_attr_reader :api_gateway, depends_on: %i[connection_manager auth_service] do
    puts "Computing api_gateway in thread: #{Thread.current.object_id}"
    initialize_api_client
  end
end

dependency_service = DependencyChainService.new
dependency_results = []

puts 'Starting dependency chain test (100 concurrent accesses to complex dependency)...'

dependency_threads = 100.times.map do |i|
  Thread.new do
    gateway = dependency_service.api_gateway

    dependency_results << {
      thread: i,
      gateway_id: gateway.object_id,
      base_config_computed: dependency_service.base_config_computed?,
      connection_manager_computed: dependency_service.connection_manager_computed?,
      auth_service_computed: dependency_service.auth_service_computed?,
      api_gateway_computed: dependency_service.api_gateway_computed?
    }
  end
end

dependency_start = Time.now
dependency_threads.each(&:join)
dependency_duration = Time.now - dependency_start

puts "\n Dependency Chain Results:"
puts "  Duration: #{(dependency_duration * 1000).round(2)}ms"
puts "  All dependencies computed: #{dependency_results.all? { |r| r[:api_gateway_computed] }}"

gateway_ids = dependency_results.map { |r| r[:gateway_id] }.uniq
puts "  Unique gateway objects: #{gateway_ids.size} (should be 1)"

dependency_passed = gateway_ids.size == 1
puts "  Result: #{dependency_passed ? '✅ PASS' : '❌ FAIL'} - Dependency resolution works correctly"

puts "\n" + '=' * 60 + "\n"

puts 'TEST 4: Reset and Recovery Under Load'
puts 'Testing reset operations during concurrent access (production maintenance scenario)'
puts '-' * 60

class ResetTestService
  extend LazyInit
  include ProductionOperations

  lazy_attr_reader :service_config do
    load_database_config
  end
end

reset_service = ResetTestService.new
reset_results = []
reset_stats = { resets: 0, access_attempts: 0, successes: 0 }

puts 'Starting reset test (readers + periodic resets)...'

reader_threads = 20.times.map do |i|
  Thread.new do
    50.times do |attempt|
      reset_stats[:access_attempts] += 1
      config = reset_service.service_config
      reset_results << { thread: i, attempt: attempt, config_id: config.object_id }
      reset_stats[:successes] += 1
      sleep(0.01)
    rescue StandardError => e
    end
  end
end

reset_thread = Thread.new do
  8.times do
    sleep(0.1)
    reset_service.reset_service_config!
    reset_stats[:resets] += 1
    puts "  Reset #{reset_stats[:resets]} performed"
  end
end

[*reader_threads, reset_thread].each(&:join)

puts "\n Reset and Recovery Results:"
puts "  Total access attempts: #{reset_stats[:access_attempts]}"
puts "  Successful accesses: #{reset_stats[:successes]}"
puts "  Resets performed: #{reset_stats[:resets]}"
puts "  Success rate: #{((reset_stats[:successes].to_f / reset_stats[:access_attempts]) * 100).round(1)}%"

unique_configs = reset_results.map { |r| r[:config_id] }.uniq
puts "  Unique config objects: #{unique_configs.size} (should be > 1 due to resets)"

reset_passed = unique_configs.size > 1 && reset_stats[:successes] > 0
puts "  Result: #{reset_passed ? '✅ PASS' : '❌ FAIL'} - Reset and recovery works correctly"

puts "\n" + '=' * 60 + "\n"

all_tests_passed = spike_passed && worker_passed && dependency_passed && reset_passed

puts ' === FINAL THREAD SAFETY SUMMARY ==='
puts "Test Environment: Ruby #{RUBY_VERSION}, #{RbConfig::CONFIG['target_cpu']}"
puts "Platform: #{RUBY_PLATFORM}"
puts ''
puts 'Results:'
puts "  ✅ Traffic Spike (200 concurrent): #{spike_passed ? 'PASS' : 'FAIL'}"
puts "  ✅ Sustained Load (1500 operations): #{worker_passed ? 'PASS' : 'FAIL'}"
puts "  ✅ Dependency Chain (100 concurrent): #{dependency_passed ? 'PASS' : 'FAIL'}"
puts "  ✅ Reset Recovery (periodic resets): #{reset_passed ? 'PASS' : 'FAIL'}"
puts ''
puts "Overall Result: #{all_tests_passed ? '✅ ALL TESTS PASSED' : '❌ SOME TESTS FAILED'}"
puts ''
