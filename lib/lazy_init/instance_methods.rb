# frozen_string_literal: true

module LazyInit
  # Provides instance-level utility methods for lazy initialization patterns.
  #
  # This module is automatically included when a class includes LazyInit (as opposed to extending it).
  # It provides method-local memoization capabilities that are useful for expensive computations
  # that need to be cached per method call location rather than per attribute.
  #
  # The lazy_once method is particularly powerful as it provides automatic caching based on
  # the caller location, making it easy to add memoization to any method without explicit
  # cache key management.
  #
  # @example Basic lazy value creation
  #   class DataProcessor
  #     include LazyInit
  #
  #     def process_data
  #       expensive_parser = lazy { ExpensiveParser.new }
  #       expensive_parser.value.parse(data)
  #     end
  #   end
  #
  # @example Method-local memoization
  #   class ApiClient
  #     include LazyInit
  #
  #     def fetch_user_data(user_id)
  #       lazy_once(ttl: 5.minutes) do
  #         expensive_api_call(user_id)
  #       end
  #     end
  #   end
  #
  # @since 0.1.0
  module InstanceMethods
    # Create a standalone lazy value container.
    #
    # This is a simple factory method that creates a LazyValue instance.
    # Useful when you need lazy initialization behavior but don't want to
    # define a formal lazy attribute on the class.
    #
    # @param block [Proc] the computation to execute lazily
    # @return [LazyValue] a new lazy value container
    # @raise [ArgumentError] if no block is provided
    #
    # @example Standalone lazy computation
    #   def expensive_calculation
    #     result = lazy { perform_heavy_computation }
    #     result.value
    #   end
    def lazy(&block)
      LazyValue.new(&block)
    end

    # Method-local memoization with automatic cache key generation.
    #
    # Caches computation results based on the caller location (file and line number),
    # providing automatic memoization without explicit key management. Each unique
    # call site gets its own cache entry with optional TTL and LRU eviction.
    #
    # This is particularly useful for expensive computations in methods that are
    # called frequently but where the result can be cached for a period of time.
    #
    # @param max_entries [Integer, nil] maximum cache entries before LRU eviction
    # @param ttl [Numeric, nil] time-to-live in seconds for cache entries
    # @param block [Proc] the computation to cache
    # @return [Object] the computed or cached value
    # @raise [ArgumentError] if no block is provided
    #
    # @example Simple method memoization
    #   def expensive_data_processing
    #     lazy_once do
    #       perform_heavy_computation
    #     end
    #   end
    #
    # @example With TTL and size limits
    #   def fetch_external_data
    #     lazy_once(ttl: 30.seconds, max_entries: 100) do
    #       external_api.fetch_data
    #     end
    #   end
    def lazy_once(max_entries: nil, ttl: nil, &block)
      raise ArgumentError, 'Block is required' unless block

      # apply global configuration defaults
      max_entries ||= LazyInit.configuration.max_lazy_once_entries
      ttl ||= LazyInit.configuration.lazy_once_ttl

      # generate cache key from caller location for automatic memoization
      call_location = caller_locations(1, 1).first
      location_key = "#{call_location.path}:#{call_location.lineno}"

      # ensure thread-safe cache initialization
      @lazy_once_mutex ||= Mutex.new

      # fast path: check cache outside mutex for performance
      if @lazy_once_cache&.key?(location_key)
        cached_entry = @lazy_once_cache[location_key]

        # handle TTL expiration if configured
        if ttl && Time.now - cached_entry[:created_at] > ttl
          @lazy_once_mutex.synchronize do
            # double-check TTL after acquiring lock
            if @lazy_once_cache&.key?(location_key)
              cached_entry = @lazy_once_cache[location_key]
              if Time.now - cached_entry[:created_at] > ttl
                @lazy_once_cache.delete(location_key)
              else
                # entry is still valid, update access tracking and return
                cached_entry[:access_count] += 1
                cached_entry[:last_accessed] = Time.now if ttl
                return cached_entry[:value]
              end
            end
          end
        else
          # cache hit: update access tracking in thread-safe manner
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

      # slow path: compute value and cache result
      @lazy_once_mutex.synchronize do
        # double-check pattern: another thread might have computed while we waited
        if @lazy_once_cache&.key?(location_key)
          cached_entry = @lazy_once_cache[location_key]

          # verify TTL hasn't expired while we waited for the lock
          if ttl && Time.now - cached_entry[:created_at] > ttl
            @lazy_once_cache.delete(location_key)
          else
            cached_entry[:access_count] += 1
            cached_entry[:last_accessed] = Time.now if ttl
            return cached_entry[:value]
          end
        end

        # initialize cache storage if this is the first lazy_once call
        @lazy_once_cache ||= {}

        # perform LRU cleanup if cache is getting too large
        cleanup_lazy_once_cache_simple!(max_entries) if @lazy_once_cache.size >= max_entries

        # compute the value and store in cache with minimal metadata
        begin
          computed_value = block.call

          # create cache entry with minimal required metadata for performance
          cache_entry = {
            value: computed_value,
            access_count: 1
          }

          # add optional metadata only when features are actually used
          cache_entry[:created_at] = Time.now if ttl
          cache_entry[:last_accessed] = Time.now if ttl

          @lazy_once_cache[location_key] = cache_entry
          computed_value
        rescue StandardError => e
          # don't cache exceptions to keep implementation simple
          raise
        end
      end
    end

    # Clear all cached lazy_once values for this instance.
    #
    # This method is thread-safe and can be used to reset all method-local
    # memoization caches, useful for testing or when you need to ensure
    # fresh computation on subsequent calls.
    #
    # @return [void]
    def clear_lazy_once_values!
      @lazy_once_mutex ||= Mutex.new
      @lazy_once_mutex.synchronize do
        @lazy_once_cache&.clear
      end
    end

    # Get detailed information about all cached lazy_once values.
    #
    # Returns a hash mapping call locations to their cache metadata,
    # useful for debugging and understanding cache behavior.
    #
    # @return [Hash<String, Hash>] mapping of call locations to cache information
    #
    # @example Inspecting cache state
    #   processor = DataProcessor.new
    #   processor.some_cached_method
    #   info = processor.lazy_once_info
    #   puts info # => { "/path/to/file.rb:42" => { computed: true, access_count: 1, ... } }
    def lazy_once_info
      @lazy_once_mutex ||= Mutex.new
      @lazy_once_mutex.synchronize do
        return {} unless @lazy_once_cache

        result = {}
        @lazy_once_cache.each do |location_key, entry|
          result[location_key] = {
            computed: true, # always true in this implementation since we don't cache exceptions
            exception: false, # we don't cache exceptions for simplicity
            created_at: entry[:created_at],
            access_count: entry[:access_count],
            last_accessed: entry[:last_accessed]
          }
        end
        result
      end
    end

    # Get statistical summary of lazy_once cache usage.
    #
    # Provides aggregated information about cache performance including
    # total entries, access patterns, and timing information.
    #
    # @return [Hash] statistical summary of cache usage
    #
    # @example Monitoring cache performance
    #   stats = processor.lazy_once_statistics
    #   puts "Cache hit ratio: #{stats[:total_accesses] / stats[:total_entries].to_f}"
    #   puts "Average accesses per entry: #{stats[:average_accesses]}"
    def lazy_once_statistics
      @lazy_once_mutex ||= Mutex.new
      @lazy_once_mutex.synchronize do
        # return empty stats if no cache exists yet
        unless @lazy_once_cache
          return {
            total_entries: 0,
            computed_entries: 0,
            oldest_entry: nil,
            newest_entry: nil,
            total_accesses: 0,
            average_accesses: 0
          }
        end

        total_entries = @lazy_once_cache.size
        total_accesses = @lazy_once_cache.values.sum { |entry| entry[:access_count] }

        # extract creation timestamps for age analysis (Ruby 2.6 compatible)
        created_times = @lazy_once_cache.values.map { |entry| entry[:created_at] }.compact

        {
          total_entries: total_entries,
          computed_entries: total_entries, # all cached entries are successfully computed
          oldest_entry: created_times.min,
          newest_entry: created_times.max,
          total_accesses: total_accesses,
          average_accesses: total_entries > 0 ? total_accesses / total_entries.to_f : 0
        }
      end
    end

    private

    # Perform simple LRU-style cache cleanup to prevent unbounded memory growth.
    #
    # Removes the least recently used entries when cache size exceeds limits.
    # Uses a simple strategy: remove 25% of entries to avoid frequent cleanup overhead.
    #
    # @param max_entries [Integer] the maximum number of entries to maintain
    # @return [void]
    def cleanup_lazy_once_cache_simple!(max_entries)
      return unless @lazy_once_cache.size > max_entries

      # remove 25% of entries to avoid frequent cleanup cycles
      entries_to_remove = @lazy_once_cache.size - (max_entries * 0.75).to_i

      # use LRU eviction if we have access time tracking, otherwise just remove oldest entries
      if @lazy_once_cache.values.first[:last_accessed] # has TTL metadata with access tracking
        # sort by last access time and remove least recently used
        sorted_entries = @lazy_once_cache.sort_by { |_, entry| entry[:last_accessed] || Time.at(0) }
        sorted_entries.first(entries_to_remove).each { |key, _| @lazy_once_cache.delete(key) }
      else
        # no access time tracking available, just remove arbitrary entries for speed
        keys_to_remove = @lazy_once_cache.keys.first(entries_to_remove)
        keys_to_remove.each { |key| @lazy_once_cache.delete(key) }
      end
    end
  end
end
