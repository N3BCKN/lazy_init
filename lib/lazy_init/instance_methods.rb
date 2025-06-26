# frozen_string_literal: true

module LazyInit
  # Instance methods added to classes that include LazyInit
  module InstanceMethods
    DEFAULT_LAZY_ONCE_CONFIG = {
      max_entries: 1000,
      ttl: nil
    }.freeze
    # Creates a standalone lazy value
    #
    # Useful for creating one-off lazy values without defining them
    # as attributes on the class.
    #
    # @param block [Proc] the initialization block
    # @return [LazyValue] a new lazy value instance
    # @raise [ArgumentError] if no block is given
    #
    # @example Creating a lazy computation
    #   def expensive_data
    #     @expensive_data ||= lazy do
    #       # This block runs only once
    #       fetch_and_process_data
    #     end
    #   end
    #
    #   # Usage
    #   data = expensive_data.value  # Computed on first call
    #   data = expensive_data.value  # Returns cached result
    def lazy(&block)
      LazyValue.new(&block)
    end

    # Creates a location-based lazy value that's computed once per call site
    #
    # This is useful for lazy initialization within methods where you want
    # the same value to be returned on subsequent calls to the same location
    # in code, but different values for different call sites.
    #
    # @param block [Proc] the initialization block
    # @return [Object] the computed value
    # @raise [ArgumentError] if no block is given
    #
    # @example Method-local lazy initialization
    #   def process_data
    #     # This expensive computation happens once per method
    #     parser = lazy_once { create_expensive_parser }
    #
    #     # Use parser...
    #     parser.parse(data)
    #   end
    #
    #   def other_method
    #     # This gets a different parser instance
    #     parser = lazy_once { create_expensive_parser }
    #     # ...
    #   end
    def lazy_once(max_entries: nil, ttl: nil, &block)
      raise ArgumentError, 'Block is required' unless block

      max_entries ||= LazyInit.configuration.max_lazy_once_entries
      ttl ||= LazyInit.configuration.lazy_once_ttl

      # Initialize storage if needed
      @lazy_once_values ||= {}
      @lazy_once_metadata ||= {}

      # Cleanup if needed
      cleanup_lazy_once_cache!(ttl: ttl, max_entries: max_entries)

      # Use caller location as key
      call_location = caller_locations(1, 1).first
      location_key = "#{call_location.path}:#{call_location.lineno}"

      # Get or create lazy value for this location
      unless @lazy_once_values.key?(location_key)
        @lazy_once_values[location_key] = LazyValue.new(&block)
        @lazy_once_metadata[location_key] = {
          created_at: Time.now,
          access_count: 0,
          last_accessed: Time.now
        }
      end

      # Update metadata
      metadata = @lazy_once_metadata[location_key]
      metadata[:access_count] += 1
      metadata[:last_accessed] = Time.now

      @lazy_once_values[location_key].value
    end

    # Clears all lazy_once values for this instance
    #
    # This can be useful for testing or when you want to force
    # re-computation of all lazy_once values.
    #
    # @return [void]
    def clear_lazy_once_values!
      @lazy_once_values&.clear
      @lazy_once_metadata&.clear
    end

    # Returns information about lazy_once values for debugging
    #
    # @return [Hash] mapping of locations to their computation status
    def lazy_once_info
      return {} unless @lazy_once_values

      result = {}
      @lazy_once_values.each do |location_key, lazy_value|
        metadata = @lazy_once_metadata[location_key] || {}
        result[location_key] = {
          computed: lazy_value.computed?,
          exception: lazy_value.exception?,
          created_at: metadata[:created_at],
          access_count: metadata[:access_count],
          last_accessed: metadata[:last_accessed]
        }
      end
      result
    end

    # Returns comprehensive statistics about lazy_once cache usage.
    #
    # Provides detailed information about cached values including entry counts,
    # access patterns, and temporal data for monitoring and debugging purposes.
    # Returns empty hash if no lazy_once values have been created.
    #
    # @return [Hash<Symbol, Object>] statistics hash containing:
    #   * :total_entries [Integer] - total number of cached values
    #   * :computed_entries [Integer] - number of successfully computed values
    #   * :oldest_entry [Time, nil] - timestamp of oldest cache entry
    #   * :newest_entry [Time, nil] - timestamp of newest cache entry
    #   * :total_accesses [Integer] - sum of all access counts across entries
    #   * :average_accesses [Float] - average accesses per cache entry
    def lazy_once_statistics
      return {} unless @lazy_once_values && @lazy_once_metadata

      {
        total_entries: @lazy_once_values.size,
        computed_entries: @lazy_once_values.count { |_, lazy_val| lazy_val.computed? },
        oldest_entry: @lazy_once_metadata.values.map { |m| m[:created_at] }.min,
        newest_entry: @lazy_once_metadata.values.map { |m| m[:created_at] }.max,
        total_accesses: @lazy_once_metadata.values.sum { |m| m[:access_count] },
        average_accesses: if @lazy_once_metadata.empty?
                            0
                          else
                            @lazy_once_metadata.values.sum { |m|
                              m[:access_count]
                            } / @lazy_once_metadata.size.to_f
                          end
      }
    end

    private

    def cleanup_lazy_once_cache!(ttl:, max_entries:)
      return unless @lazy_once_values && !@lazy_once_values.empty?

      # TTL cleanup
      if ttl
        cutoff_time = Time.now - ttl
        expired_keys = @lazy_once_metadata.select { |_, meta| meta[:created_at] < cutoff_time }.keys
        expired_keys.each do |key|
          @lazy_once_values.delete(key)
          @lazy_once_metadata.delete(key)
        end
      end

      # Size-based cleanup (remove least recently used)
      return unless @lazy_once_values.size > max_entries

      excess_count = @lazy_once_values.size - max_entries

      # Sort by last_accessed (oldest first)
      sorted_by_access = @lazy_once_metadata.sort_by { |_, meta| meta[:last_accessed] }
      keys_to_remove = sorted_by_access.first(excess_count).map(&:first)

      keys_to_remove.each do |key|
        @lazy_once_values.delete(key)
        @lazy_once_metadata.delete(key)
      end
    end
  end
end
