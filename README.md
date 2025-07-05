# LazyInit

Thread-safe lazy initialization patterns for Ruby with automatic dependency resolution, memory management, and performance optimization.

[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%202.6-red.svg)](https://www.ruby-lang.org/)
[![Gem Version](https://badge.fury.io/rb/lazy_init.svg)](https://badge.fury.io/rb/lazy_init)
[![Build Status](https://github.com/N3BCKN/lazy_init/workflows/CI/badge.svg)](https://github.com/N3BCKN/lazy_init/actions)

## Table of Contents

- [Problem Statement](#problem-statement)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Core Features](#core-features)
- [API Reference](#api-reference)
  - [Instance Attributes](#instance-attributes)
  - [Class Variables](#class-variables)
  - [Instance Methods](#instance-methods)
  - [Configuration](#configuration)
- [Advanced Usage](#advanced-usage)
  - [Dependency Resolution](#dependency-resolution)
  - [Timeout Protection](#timeout-protection)
  - [Memory Management](#memory-management)
- [Common Use Cases](#common-use-cases)
- [Error Handling](#error-handling)
- [Performance](#performance)
- [Thread Safety](#thread-safety)
  - [Thread Safety Deep Dive](#thread-safety-deep-dive)
- [Compatibility](#compatibility)
- [Testing](#testing)
- [Migration Guide](#migration-guide)
- [When NOT to Use LazyInit](#when-not-to-use-lazyinit)
- [FAQ](#faq)
- [Contributing](#contributing)
- [License](#license)

## Problem Statement

Ruby's common lazy initialization pattern using `||=` is **not thread-safe** and can cause race conditions in multi-threaded environments:

```ruby
# ❌ Thread-unsafe (common pattern)
def expensive_calculation
  @result ||= perform_heavy_computation  # Race condition possible!
end

# ✅ Thread-safe (LazyInit solution)
lazy_attr_reader :expensive_calculation do
  perform_heavy_computation
end
```
LazyInit provides thread-safe lazy initialization with zero race conditions, automatic dependency resolution, and intelligent performance optimization.

## Installation
Add this line to your application's Gemfile:
```ruby 
gem 'lazy_init'
```
And then execute:
```ruby
bundle install
```
Or install it yourself as:
```ruby
 gem install lazy_init
```
## Requirements:

- Ruby 2.6 or higher
- No external dependencies

## Quick Start
### Basic Usage

```ruby
class ApiClient
  extend LazyInit
  
  lazy_attr_reader :connection do
    puts "Establishing connection..."
    HTTPClient.new(api_url)
  end
end

client = ApiClient.new
# No connection established yet

client.connection  # "Establishing connection..." - computed once
client.connection  # Returns cached result (thread-safe)
```

### With Dependencies
```ruby
class WebService
  extend LazyInit
  
  lazy_attr_reader :config do
    YAML.load_file('config.yml')
  end
  
  lazy_attr_reader :database, depends_on: [:config] do
    Database.connect(config['database_url'])
  end
  
  lazy_attr_reader :api_client, depends_on: [:config, :database] do
    ApiClient.new(
      url: config['api_url'],
      database: database
    )
  end
end

service = WebService.new
service.api_client  # Automatically resolves: config → database → api_client
```

## Core Features
 ### Thread Safety

- Eliminates all race conditions with optimized double-checked locking
- Circular dependency detection prevents infinite loops
- Thread-safe reset for testing and error recovery

### Automatic Dependency Resolution

- Declarative dependencies with depends_on option
- Automatic resolution order computation
- Intelligent caching to avoid redundant work

### Performance Optimization

- Three-tier implementation strategy based on complexity
- 5-6x overhead vs manual ||= (significantly faster than alternatives)
- Memory-efficient with automatic cleanup

```ruby
# Simple inline (fastest)
lazy_attr_reader :simple_value do
  "simple"
end

# Optimized dependency (medium)
lazy_attr_reader :dependent_value, depends_on: [:simple_value] do
  "depends on #{simple_value}"
end

# Full LazyValue (complete features)
lazy_attr_reader :complex_value, timeout: 5, depends_on: [:multiple, :deps] do
  "complex computation"
end
```

### Memory Management

- Automatic cache cleanup prevents memory leaks
- LRU eviction for method-local caching
- TTL support for time-based expiration

## API Reference
### Instance Attributes
```ruby
lazy_attr_reader(name, **options, &block)
```
Defines a thread-safe lazy-initialized attribute.
#### Parameters:

- name (Symbol/String): Attribute name
- timeout (Numeric, optional): Timeout in seconds for computation
- depends_on (Array<Symbol>/Symbol, optional): Dependencies to resolve first
- block (Proc): Computation block

#### Generated Methods:

- #{name}: Returns the computed value
- #{name}_computed?: Returns true if value has been computed
- reset_#{name}!: Resets to uncomputed state

#### Examples:
```ruby
rubyclass ServiceManager
  extend LazyInit
  
  # Simple lazy attribute
  lazy_attr_reader :expensive_service do
    ExpensiveService.new
  end
  
  # With timeout protection
  lazy_attr_reader :external_api, timeout: 10 do
    ExternalAPI.connect
  end
  
  # With dependencies
  lazy_attr_reader :configured_service, depends_on: [:config] do
    ConfiguredService.new(config)
  end
end

manager = ServiceManager.new
manager.expensive_service_computed?  # => false
manager.expensive_service           # Creates service
manager.expensive_service_computed?  # => true
manager.reset_expensive_service!    # Resets for re-computation
```

### Class Variables
```ruby
lazy_class_variable(name, **options, &block)
```
Defines a thread-safe lazy-initialized class variable shared across all instances.
#### Parameters:

 - Same as lazy_attr_reader

#### Generated Methods:

- Class-level: ClassName.#{name}, ClassName.#{name}\_computed?, ClassName.reset\_#{name}!
- Instance-level: #{name}, #{name}\_computed?, reset\_#{name}! (delegates to class)

#### Example:
```ruby
class DatabaseManager
  extend LazyInit
  
  lazy_class_variable :connection_pool do
    ConnectionPool.new(size: 20, timeout: 30)
  end
end

# Shared across all instances
db1 = DatabaseManager.new
db2 = DatabaseManager.new
db1.connection_pool.equal?(db2.connection_pool)  # => true

# Class-level access
DatabaseManager.connection_pool                  # Direct access
DatabaseManager.reset_connection_pool!           # Reset for all instances
```

### Instance Methods
#### Include LazyInit (instead of extending) to get instance-level utilities:
```ruby
class DataProcessor
  include LazyInit  # Note: include, not extend
end
```
**lazy(&block)**

 Creates a standalone lazy value container.
```ruby
def expensive_calculation
  result = lazy { perform_heavy_computation }
  result.value
end
```


__lazy_once(**options, &block)__

 Method-scoped lazy initialization with automatic cache key generation.
#### Parameters:

- max_entries (Integer): Maximum cache entries before LRU eviction
- ttl (Numeric): Time-to-live in seconds for cache entries

#### Example:
``` ruby
class DataAnalyzer
  include LazyInit
  
  def analyze_data(dataset_id)
    lazy_once(ttl: 5.minutes, max_entries: 100) do
      expensive_analysis(dataset_id)
    end
  end
end
```

**clear_lazy_once_values!**

Clears all cached lazy_once values for the instance.

**lazy_once_statistics**

Returns cache statistics for debugging and monitoring.

```ruby 
stats = processor.lazy_once_statistics
# => {
#   total_entries: 25,
#   computed_entries: 25,
#   total_accesses: 150,
#   average_accesses: 6.0,
#   oldest_entry: 2025-07-01 10:00:00,
#   newest_entry: 2024-07-01 10:30:00
# }
```

### Configuration
Configure global behavior:
```ruby
LazyInit.configure do |config|
  config.default_timeout = 30
  config.max_lazy_once_entries = 5000
  config.lazy_once_ttl = 1.hour
end
```

#### Configuration Options:

- **default_timeout**: Default timeout for all lazy attributes (default: nil)
- **max_lazy_once_entries**: Maximum entries in lazy_once cache (default: 1000)
- **lazy_once_ttl**: Default TTL for lazy_once entries (default: nil)

## Advanced Usage
### Dependency Resolution
#### LazyInit automatically resolves dependencies in the correct order:
```ruby
rubyclass ComplexService
  extend LazyInit
  
  lazy_attr_reader :config do
    load_configuration
  end
  
  lazy_attr_reader :database, depends_on: [:config] do
    Database.connect(config.database_url)
  end
  
  lazy_attr_reader :cache, depends_on: [:config] do
    Cache.new(config.cache_settings)
  end
  
  lazy_attr_reader :processor, depends_on: [:database, :cache] do
    DataProcessor.new(database: database, cache: cache)
  end
end

service = ComplexService.new
service.processor  # Resolves: config → database & cache → processor
```

#### Circular Dependency Detection:
```ruby
lazy_attr_reader :service_a, depends_on: [:service_b] do
  "A"
end

lazy_attr_reader :service_b, depends_on: [:service_a] do
  "B"
end

service.service_a  # Raises: LazyInit::DependencyError
```

### Timeout Protection
#### Protect against hanging computations:

```ruby
class ExternalService
  extend LazyInit
  
  lazy_attr_reader :slow_api, timeout: 5 do
    HTTPClient.get('http://very-slow-api.com/data')
  end
end

service = ExternalService.new
begin
  service.slow_api
rescue LazyInit::TimeoutError => e
  puts "API call timed out: #{e.message}"
end
```

### Memory Management
#### LazyInit includes sophisticated memory management:
```ruby
class MemoryAwareService
  include LazyInit
  
  def process_data(data_id)
    # Automatic cleanup when cache grows too large
    lazy_once(max_entries: 50, ttl: 10.minutes) do
      expensive_data_processing(data_id)
    end
  end
  
  def cleanup!
    clear_lazy_once_values!  # Manual cleanup
  end
end
```

## Common Use Cases
#### Rails Application Services
```ruby
class UserService
  extend LazyInit
  
  lazy_attr_reader :redis_client do
    Redis.new(url: Rails.application.credentials.redis_url)
  end
  
  lazy_class_variable :connection_pool do
    ConnectionPool.new(size: Rails.env.production? ? 20 : 5)
  end
  
  lazy_attr_reader :email_service, depends_on: [:redis_client] do
    EmailService.new(cache: redis_client)
  end
end
```

#### Background Jobs
```ruby
class ImageProcessorJob
  extend LazyInit
  
  lazy_attr_reader :image_processor do
    ImageProcessor.new(memory_limit: '512MB')
  end
  
  lazy_attr_reader :cloud_storage, timeout: 10 do
    CloudStorage.new(credentials: ENV['CLOUD_CREDENTIALS'])
  end
  
  def perform(image_id)
    processed = image_processor.process(image_id)
    cloud_storage.upload(processed)
  end
end
```
#### Microservices
```ruby
class PaymentService
  extend LazyInit
  
  lazy_attr_reader :config do
    ServiceConfig.load('payment_service')
  end
  
  lazy_attr_reader :database, depends_on: [:config] do
    Database.connect(config.database_url)
  end
  
  lazy_attr_reader :payment_gateway, depends_on: [:config], timeout: 15 do
    PaymentGateway.new(
      api_key: config.payment_api_key,
      environment: config.environment
    )
  end
end
```
### Rails Concerns
```ruby
module Cacheable
  extend ActiveSupport::Concern
  
  included do
    extend LazyInit
    
    lazy_attr_reader :cache_client do
      Rails.cache
    end
  end
  
  def cached_method(key)
    lazy_once(ttl: 1.hour) do
      expensive_computation(key)
    end
  end
end
```
## Error Handling
LazyInit provides predictable error behavior:
```ruby
class ServiceWithErrors
  extend LazyInit
  
  lazy_attr_reader :failing_service do
    raise StandardError, "Service unavailable"
  end
  
  lazy_attr_reader :timeout_service, timeout: 1 do
    sleep(5)  # Will timeout
    "Success"
  end
end

service = ServiceWithErrors.new

# Exceptions are cached and re-raised consistently
begin
  service.failing_service
rescue StandardError => e
  puts "First call: #{e.message}"
end

begin
  service.failing_service  # Same exception re-raised (cached)
rescue StandardError => e
  puts "Second call: #{e.message}"  # Same exception instance
end

# Check error state
service.failing_service_computed?  # => false (failed computation)

# Reset allows retry
service.reset_failing_service!
service.failing_service  # => Attempts computation again

# Timeout errors
begin
  service.timeout_service
rescue LazyInit::TimeoutError => e
  puts "Timeout: #{e.message}"
  # Subsequent calls raise the same timeout error
end
```
#### Exception Types
```ruby
LazyInit::Error                      # Base error class
LazyInit::InvalidAttributeNameError  # Invalid attribute names
LazyInit::TimeoutError               # Timeout exceeded
LazyInit::DependencyError           # Circular dependencies
Performance
LazyInit is optimized for production use:
```
## Performance

Realistic benchmark results (x86_64-darwin19, Ruby 3.0.2):

- Initial computation: ~identical (LazyInit setup overhead negligible)
- Cached access: 3.5x slower than manual ||= 
-100,000 calls: Manual 13ms, LazyInit 45ms
- In practice: For expensive operations (5-50ms), the 0.0004ms per call overhead is negligible.
- Trade-off: 3.5x cached access cost for 100% thread safety

[Full details can be found here](https://github.com/N3BCKN/lazy_init/blob/main/benchmarks/benchmark_performance.rb)

### Optimization Strategies
LazyInit automatically selects the best implementation:

- Simple inline (no dependencies, no timeout): Maximum performance
- Optimized dependency (single dependency): Balanced performance
- Full LazyValue (complex scenarios): Full feature set


## Thread Safety
LazyInit provides comprehensive thread safety guarantees:
### Thread Safety Features

- Double-checked locking for optimal performance
- Per-attribute mutexes to avoid global locks
- Atomic state transitions to prevent race conditions
- Exception safety with proper cleanup

#### Example: Concurrent Access
```ruby
class ThreadSafeService
  extend LazyInit
  
  lazy_attr_reader :shared_resource do
    puts "Creating resource in thread #{Thread.current.object_id}"
    ExpensiveResource.new
  end
end

service = ThreadSafeService.new

# Multiple threads accessing the same attribute
threads = 10.times.map do |i|
  Thread.new do
    puts "Thread #{i}: #{service.shared_resource.object_id}"
  end
end

threads.each(&:join)
# Output: All threads get the same object_id (single computation)
```
### Thread Safety Deep Dive
LazyInit uses several techniques to ensure thread safety:

- Double-checked locking: Fast path avoids synchronization after computation
- Per-attribute mutexes: No global locks that could cause bottlenecks
- Atomic state transitions: Prevents race conditions during computation
- Exception safety: Proper cleanup even when computations fail

[Full report with benchmark here](https://github.com/N3BCKN/lazy_init/blob/main/benchmarks/benchmark_threads.rb)

#### Thread Safety benchmark 
- 200 concurrent requests: 0 race conditions
- 6,000+ operations/second sustained throughput  
- Complex dependency chains: 100% reliable
- Zero-downtime resets: 100% success rate
- Tested on Ruby 3.0.2, macOS (Intel)

## Compatibility

- Ruby: 2.6, 2.7, 3.0, 3.1, 3.2, 3.3+
- Rails: 5.2+ (optional, no Rails dependency required)
- Thread-safe: Yes, across all Ruby implementations (MRI, JRuby, TruffleRuby)
- Ractor-safe: Planned for future versions
- Versioning: LazyInit follows semantic versioning

## Testing

#### RSpec Integration
```ruby
RSpec.describe UserService do
  let(:service) { UserService.new }
  
  describe '#expensive_calculation' do
    it 'computes value lazily' do
      expect(service.expensive_calculation_computed?).to be false
      
      result = service.expensive_calculation
      expect(result).to be_a(String)
      expect(service.expensive_calculation_computed?).to be true
    end
    
    it 'returns same value on multiple calls' do
      first_call = service.expensive_calculation
      second_call = service.expensive_calculation
      
      expect(first_call).to be(second_call)  # Same object
    end
    
    it 'can be reset for fresh computation' do
      old_value = service.expensive_calculation
      service.reset_expensive_calculation!
      new_value = service.expensive_calculation
      
      expect(new_value).not_to be(old_value)
    end
  end
end
```
#### Test Helpers
```ruby
# Custom helpers for testing
module LazyInitTestHelpers
  def reset_all_lazy_attributes(object)
    object.class.lazy_initializers.each_key do |attr_name|
      object.send("reset_#{attr_name}!")
    end
  end
end

RSpec.configure do |config|
  config.include LazyInitTestHelpers
end
```

#### Rails Testing Considerations
```ruby
# In Rails, be careful with class variables during code reloading
RSpec.configure do |config|
  config.before(:each) do
    # Reset class variables in development/test
    MyService.reset_connection_pool! if defined?(MyService)
  end
end
```
## Migration Guide
#### From Manual ||= Pattern
Before:
```ruby
class LegacyService
  def config
    @config ||= YAML.load_file('config.yml')
  end
  
  def database
    @database ||= Database.connect(config['url'])
  end
end
```
After:
```ruby
class ModernService
  extend LazyInit
  
  lazy_attr_reader :config do
    YAML.load_file('config.yml')
  end
  
  lazy_attr_reader :database, depends_on: [:config] do
    Database.connect(config['url'])
  end
end
```

### Migration Benefits

- Thread safety: Automatic protection against race conditions
- Dependency management: Explicit dependency declaration
- Error handling: Built-in timeout and exception management
- Testing: Easier state management in tests

### Gradual Migration Strategy

- Start with new lazy attributes using LazyInit
- Identify critical thread-unsafe ||= patterns
- Convert high-risk areas first
- Add dependency declarations where beneficial
- Remove manual patterns over time

## When NOT to Use LazyInit
Consider alternatives in these scenarios:

- Simple value caching where manual ||= suffices and thread safety isn't needed
- Performance-critical hot paths in tight loops where every microsecond counts
- Single-threaded applications with basic caching needs
- Primitive value caching (strings, numbers, booleans) where overhead outweighs benefits
- Very simple Rails applications without complex service layers

## FAQ
Q: How does performance compare to other approaches?

A: Compared to manual mutex-based solutions, LazyInit provides better developer experience with competitive performance. See benchmarks for detailed comparison with manual ||= patterns.

Q: Can I use this in Rails initializers?

A: Yes, but be careful with class variables in development mode due to code reloading.

Q: What happens during Rails code reloading?

A: Instance attributes are automatically reset. Class variables may need manual reset in development.

Q: Is there any memory overhead?

A: Minimal - about 1 mutex + 3 instance variables per lazy attribute.

Q: Can I use lazy_attr_reader with private methods?

A: Yes, the generated methods respect the same visibility as where they're defined.

Q: How do I debug dependency resolution issues?

A: Use YourClass.lazy_initializers to inspect dependency configuration and check for circular dependencies.

Q: Does this work with inheritance?

A: Yes, lazy attributes are inherited and can be overridden in subclasses.
## Contributing

1. Fork the repository
2. Create your feature branch (git checkout -b my-new-feature)
3. Write tests for your changes
4. Ensure all tests pass (bundle exec rspec)
5. Commit your changes (git commit -am 'Add some feature')
6. Push to the branch (git push origin my-new-feature)
7. Create a Pull Request

## Development Setup
```bash
git clone https://github.com/N3BCKN/lazy_init.git
cd lazy_init
bundle install
bundle exec rspec  # Run tests
```
## License
The gem is available as open source under the terms of the MIT License.
