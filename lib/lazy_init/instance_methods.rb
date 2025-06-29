# frozen_string_literal: true

module LazyInit
  # FAZA 2: Drastically optimized instance methods
  # Target: Reduce method memoization from 28.7x → 3-5x slower than manual
  #
  # KEY OPTIMIZATIONS:
  # 1. Simplified cache implementation (remove complex TTL/LRU unless needed)
  # 2. Direct hash access instead of complex metadata tracking
  # 3. Lazy cache initialization
  # 4. Optimized cleanup logic
  
  module InstanceMethods
    # Creates a standalone lazy value (optimized)
    def lazy(&block)
      # Use simple inline approach for standalone lazy values too
      LazyValue.new(&block)
    end

    # Thread-safe lazy_once with minimal overhead
    def lazy_once(max_entries: nil, ttl: nil, &block)
      raise ArgumentError, 'Block is required' unless block

      # Use global config defaults
      max_entries ||= LazyInit.configuration.max_lazy_once_entries
      ttl ||= LazyInit.configuration.lazy_once_ttl

      # Use caller location as key (fast, no complex metadata)
      call_location = caller_locations(1, 1).first
      location_key = "#{call_location.path}:#{call_location.lineno}"

      # Thread-safe cache access with double-checked locking
      @lazy_once_mutex ||= Mutex.new
      
      # Fast path check outside mutex
      if @lazy_once_cache&.key?(location_key)
        cached_entry = @lazy_once_cache[location_key]
        
        # TTL check if configured
        if ttl && Time.now - cached_entry[:created_at] > ttl
          @lazy_once_mutex.synchronize do
            # Double-check TTL inside mutex
            if @lazy_once_cache&.key?(location_key)
              cached_entry = @lazy_once_cache[location_key]
              if Time.now - cached_entry[:created_at] > ttl
                @lazy_once_cache.delete(location_key)
              else
                cached_entry[:access_count] += 1
                cached_entry[:last_accessed] = Time.now if ttl
                return cached_entry[:value]
              end
            end
          end
        else
          # Update access count in thread-safe way
          @lazy_once_mutex.synchronize do
            if @lazy_once_cache&.key?(location_key)
              cached_entry = @lazy_once_cache[location_key]
              cached_entry[:access_count] += 1
              cached_entry[:last_accessed] = Time.now if ttl
              return cached_entry[:value]
            end
          end
        end
      end

      # Slow path - need to compute
      @lazy_once_mutex.synchronize do
        # Double-check pattern
        if @lazy_once_cache&.key?(location_key)
          cached_entry = @lazy_once_cache[location_key]
          
          # Check TTL again
          if ttl && Time.now - cached_entry[:created_at] > ttl
            @lazy_once_cache.delete(location_key)
          else
            cached_entry[:access_count] += 1
            cached_entry[:last_accessed] = Time.now if ttl
            return cached_entry[:value]
          end
        end

        # Initialize cache if needed
        @lazy_once_cache ||= {}

        # Cleanup if needed (inside mutex for thread safety)
        if @lazy_once_cache.size >= max_entries
          cleanup_lazy_once_cache_simple!(max_entries)
        end

        # Compute and cache with minimal metadata
        begin
          computed_value = block.call
          
          # Store with minimal required metadata
          cache_entry = {
            value: computed_value,
            access_count: 1
          }
          
          # Only add metadata if features are used
          cache_entry[:created_at] = Time.now if ttl
          cache_entry[:last_accessed] = Time.now if ttl
          
          @lazy_once_cache[location_key] = cache_entry
          computed_value
        rescue StandardError => e
          # Don't cache exceptions in simple implementation
          raise
        end
      end
    end

    # Thread-safe clear method
    def clear_lazy_once_values!
      @lazy_once_mutex ||= Mutex.new
      @lazy_once_mutex.synchronize do
        @lazy_once_cache&.clear
      end
    end

    # Thread-safe info method with lazy computation
    def lazy_once_info
      @lazy_once_mutex ||= Mutex.new
      @lazy_once_mutex.synchronize do
        return {} unless @lazy_once_cache

        result = {}
        @lazy_once_cache.each do |location_key, entry|
          result[location_key] = {
            computed: true, # Always true in simple implementation
            exception: false, # don't cache exceptions
            created_at: entry[:created_at],
            access_count: entry[:access_count],
            last_accessed: entry[:last_accessed]
          }
        end
        result
      end
    end

    # Thread-safe statistics with minimal computation
    def lazy_once_statistics
      @lazy_once_mutex ||= Mutex.new
      @lazy_once_mutex.synchronize do
        return {
          total_entries: 0,
          computed_entries: 0,
          oldest_entry: nil,
          newest_entry: nil,
          total_accesses: 0,
          average_accesses: 0
        } unless @lazy_once_cache

        total_entries = @lazy_once_cache.size
        total_accesses = @lazy_once_cache.values.sum { |entry| entry[:access_count] }
        
        # Ruby 2.6 compatible: use map + compact instead of filter_map
        created_times = @lazy_once_cache.values.map { |entry| entry[:created_at] }.compact
        
        {
          total_entries: total_entries,
          computed_entries: total_entries, # All cached entries are computed
          oldest_entry: created_times.min,
          newest_entry: created_times.max,
          total_accesses: total_accesses,
          average_accesses: total_entries > 0 ? total_accesses / total_entries.to_f : 0
        }
      end
    end

    private

    # Ultra-simple cleanup - just remove oldest entries
    def cleanup_lazy_once_cache_simple!(max_entries)
      return unless @lazy_once_cache.size > max_entries

      # Remove 25% of entries to avoid frequent cleanup
      entries_to_remove = @lazy_once_cache.size - (max_entries * 0.75).to_i
      
      if @lazy_once_cache.values.first[:last_accessed] # Has TTL metadata
        # Sort by last_accessed (LRU eviction)
        sorted_entries = @lazy_once_cache.sort_by { |_, entry| entry[:last_accessed] || Time.at(0) }
        sorted_entries.first(entries_to_remove).each { |key, _| @lazy_once_cache.delete(key) }
      else
        # No TTL metadata - just remove arbitrary entries (fastest)
        keys_to_remove = @lazy_once_cache.keys.first(entries_to_remove)
        keys_to_remove.each { |key| @lazy_once_cache.delete(key) }
      end
    end
  end
end

# EXPECTED PERFORMANCE IMPROVEMENTS FOR LAZY_ONCE:
#
# CURRENT RESULTS:
# - Method Memoization: 28.7x slower than manual (377.8K i/s vs 10.84M i/s)
#
# TARGET RESULTS:
# - Method Memoization: 3-5x slower than manual (target: 2-3.6M i/s)
#
# KEY OPTIMIZATIONS:
# 1. LAZY CACHE INITIALIZATION - No upfront cache setup cost
# 2. SIMPLIFIED METADATA - Only store what's actually used (TTL, access counts)
# 3. FAST PATH OPTIMIZATION - Cache hit path is ultra-simple
# 4. REDUCED OBJECT ALLOCATION - Minimal metadata objects
# 5. SMART CLEANUP - Only cleanup when needed, batch removals
# 6. NO EXCEPTION CACHING - Simpler error handling
#
# MEMORY OPTIMIZATIONS:
# - No upfront cache allocation
# - Minimal metadata per cache entry
# - Batch cleanup reduces overhead
# - No complex TTL/LRU structures unless needed
#
# PERFORMANCE OPTIMIZATIONS:
# - Direct hash access (no method calls)
# - Lazy timestamp creation (only if TTL is used)
# - Simplified access counting
# - Fast path for cache hits
#
# BACKWARD COMPATIBILITY:
# - All public methods maintain same signatures
# - Statistics and info methods work as before
# - TTL and max_entries features preserved
# - Only internal implementation optimized