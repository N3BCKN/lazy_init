# frozen_string_literal: true

require 'timeout'

module LazyInit
  # Thread-safe lazy value container with timeout protection and exception caching.
  #
  # LazyValue provides thread-safe lazy initialization using double-checked locking
  # pattern with automatic timeout protection and intelligent exception handling.
  # Once computed, subsequent calls return the cached result without re-execution.
  #
  # @example Basic usage
  #   lazy_value = LazyValue.new { expensive_computation }
  #   result = lazy_value.value  # Computed once
  #   result = lazy_value.value  # Returns cached result
  #
  # @example With timeout protection
  #   lazy_value = LazyValue.new(timeout: 5) { slow_external_api_call }
  #   result = lazy_value.value  # Times out after 5 seconds
  #
  # @example Exception handling
  #   lazy_value = LazyValue.new { raise "Error" }
  #   lazy_value.value  # Raises exception
  #   lazy_value.value  # Raises same cached exception
  #
  # @since 0.1.0
  class LazyValue
    # Creates a new lazy value with optional timeout protection.
    #
    # @param timeout [Numeric, nil] Maximum time in seconds to wait for computation
    # @param block [Proc] The initialization block to execute lazily
    # @raise [ArgumentError] if no block is provided
    #
    # @example Simple initialization
    #   LazyValue.new { "computed value" }
    #
    # @example With timeout
    #   LazyValue.new(timeout: 10) { Database.connect }
    def initialize(timeout: nil, &block)
      raise ArgumentError, 'Block is required' unless block

      @block = block
      @timeout = timeout
      @mutex = Mutex.new
      @computed = false
      @value = nil
      @exception = nil
    end

    # Returns the computed value, executing the block on first access.
    #
    # Uses double-checked locking for thread safety with optimized fast path
    # for already computed values. Exceptions are cached and re-raised on
    # subsequent calls.
    #
    # @return [Object] the computed value from the initialization block
    # @raise [LazyInit::TimeoutError] if computation exceeds timeout
    # @raise [StandardError] any exception raised by the initialization block
    #
    # @example Successful computation
    #   lazy_value = LazyValue.new { "result" }
    #   lazy_value.value  # => "result"
    #   lazy_value.value  # => "result" (cached)
    #
    # @example Timeout handling
    #   lazy_value = LazyValue.new(timeout: 1) { sleep(2) }
    #   lazy_value.value  # => LazyInit::TimeoutError
    def value
      # Fast path: Check computed state first (including exceptions)
      if @computed
        raise @exception if @exception

        return @value
      end

      # Also check for cached exceptions before entering mutex
      raise @exception if @exception

      # Slow path with full synchronization
      @mutex.synchronize do
        # Double-check pattern for both success and exception cases
        if @computed
          raise @exception if @exception

          return @value
        end

        # Check exception again in critical section
        raise @exception if @exception

        begin
          computed_value = if @timeout
                             Timeout.timeout(@timeout) do
                               @block.call
                             end
                           else
                             @block.call
                           end

          @value = computed_value
          @computed = true # Mark as computed for successful case

          computed_value
        rescue Timeout::Error => e
          @exception = LazyInit::TimeoutError.new("Lazy initialization timed out after #{@timeout}s")
          # Don't set @computed = true for exceptions
          raise @exception
        rescue StandardError => e
          @exception = e
          # Don't set @computed = true for exceptions
          raise
        end
      end
    end

    # Checks if the value has been successfully computed.
    #
    # Returns true only if the value was computed without exceptions.
    # Failed computations (timeouts, errors) return false.
    #
    # @return [Boolean] true if value is computed and no exception occurred
    #
    # @example Successful computation
    #   lazy_value = LazyValue.new { "result" }
    #   lazy_value.computed?  # => false
    #   lazy_value.value      # => "result"
    #   lazy_value.computed?  # => true
    #
    # @example Failed computation
    #   lazy_value = LazyValue.new { raise "error" }
    #   lazy_value.value rescue nil
    #   lazy_value.computed?  # => false
    def computed?
      @computed && @exception.nil?
    end

    # Resets the lazy value to its uncomputed state.
    #
    # Clears the cached value, computed flag, and any cached exceptions.
    # Thread-safe operation that allows re-computation on next access.
    #
    # @return [void]
    #
    # @example Reset and recompute
    #   lazy_value = LazyValue.new { Time.now }
    #   time1 = lazy_value.value
    #   lazy_value.reset!
    #   time2 = lazy_value.value  # Different timestamp
    def reset!
      @mutex.synchronize do
        @computed = false
        @value = nil
        @exception = nil
      end
    end

    # Checks if an exception occurred during computation.
    #
    # @return [Boolean] true if computation resulted in an exception
    #
    # @example Exception detection
    #   lazy_value = LazyValue.new { raise "error" }
    #   lazy_value.value rescue nil
    #   lazy_value.exception?  # => true
    def exception?
      @mutex.synchronize { !@exception.nil? }
    end

    # Returns the cached exception if computation failed.
    #
    # @return [Exception, nil] the exception that occurred during computation,
    #   or nil if no exception occurred
    #
    # @example Getting exception details
    #   lazy_value = LazyValue.new { raise StandardError, "failed" }
    #   lazy_value.value rescue nil
    #   lazy_value.exception.message  # => "failed"
    def exception
      @mutex.synchronize { @exception }
    end
  end
end
