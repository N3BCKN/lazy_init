# frozen_string_literal: true

require 'timeout'

module LazyInit
  # Thread-safe container for lazy-initialized values with performance-optimized access.
  #
  # LazyValue provides a thread-safe wrapper around expensive computations that should
  # only be executed once. It uses a double-checked locking pattern with an ultra-fast
  # hot path that avoids synchronization overhead after initial computation.
  #
  # The implementation separates the fast path (simple instance variable access) from
  # the slow path (computation with full synchronization) for optimal performance in
  # the common case where values are accessed repeatedly after computation.
  #
  # @example Basic usage
  #   lazy_value = LazyValue.new do
  #     expensive_database_query
  #   end
  #
  #   result = lazy_value.value # computes once
  #   result = lazy_value.value # returns cached value
  #
  # @example With timeout protection
  #   lazy_value = LazyValue.new(timeout: 5) do
  #     slow_external_api_call
  #   end
  #
  #   begin
  #     result = lazy_value.value
  #   rescue LazyInit::TimeoutError
  #     puts "API call timed out"
  #   end
  #
  # @since 0.1.0
  class LazyValue
    # Create a new lazy value container.
    #
    # The computation block will be executed at most once when value() is first called.
    # Subsequent calls to value() return the cached result without re-executing the block.
    #
    # @param timeout [Numeric, nil] optional timeout in seconds for the computation
    # @param block [Proc] the computation to execute lazily
    # @raise [ArgumentError] if no block is provided
    def initialize(timeout: nil, &block)
      raise ArgumentError, 'Block is required' unless block

      @block = block
      @timeout = timeout
      @mutex = Mutex.new
      @computed = false
      @value = nil
      @exception = nil
    end

    # Get the computed value, executing the block if necessary.
    #
    # Uses an optimized double-checked locking pattern: the hot path (after computation)
    # requires only a single instance variable check and direct return. The cold path
    # (during computation) handles full synchronization and error management.
    #
    # If the computation raises an exception, that exception is cached and re-raised
    # on subsequent calls to maintain consistent behavior.
    #
    # @return [Object] the computed value
    # @raise [TimeoutError] if computation exceeds the configured timeout
    # @raise [StandardError] any exception raised by the computation block
    def value
      # hot path: optimized for repeated access after computation
      # this should be nearly as fast as direct instance variable access
      return @value if @computed

      # cold path: handle computation and synchronization
      compute_or_raise_exception
    end

    # Check if the value has been successfully computed.
    #
    # Returns false if computation hasn't started, failed with an exception,
    # or was reset. Only returns true for successful computations.
    #
    # @return [Boolean] true if value has been computed without errors
    def computed?
      @computed && @exception.nil?
    end

    # Reset the lazy value to its initial uncomputed state.
    #
    # Clears the cached value and any cached exceptions, allowing the computation
    # to be re-executed on the next call to value(). This method is thread-safe.
    #
    # @return [void]
    def reset!
      @mutex.synchronize do
        @computed = false
        @value = nil
        @exception = nil
      end
    end

    # Check if the computation resulted in a cached exception.
    #
    # This method is thread-safe and can be used to determine if value()
    # will raise an exception without actually triggering it.
    #
    # @return [Boolean] true if an exception is cached
    def exception?
      @mutex.synchronize { !@exception.nil? }
    end

    # Access the cached exception if one exists.
    #
    # Returns the actual exception object that was raised during computation,
    # or nil if no exception occurred or computation hasn't been attempted.
    #
    # @return [Exception, nil] the cached exception or nil
    def exception
      @mutex.synchronize { @exception }
    end

    private

    # Handle computation and exception management in the slow path.
    #
    # This method is separated from the main value() method to keep the hot path
    # as minimal and fast as possible. It handles all the complex logic around
    # synchronization, timeout management, and exception caching.
    #
    # @return [Object] the computed value
    # @raise [Exception] any exception from computation (after caching)
    def compute_or_raise_exception
      @mutex.synchronize do
        # double-check pattern: another thread might have computed while we waited for the lock
        return @value if @computed

        # if a previous computation failed, re-raise the cached exception
        raise @exception if @exception

        begin
          # execute computation with optional timeout protection
          computed_value = if @timeout
                             Timeout.timeout(@timeout) do
                               @block.call
                             end
                           else
                             @block.call
                           end

          # atomic state update: set value first, then mark as computed
          # this ensures @computed is only true when @value contains valid data
          @value = computed_value
          @computed = true

          computed_value
        rescue Timeout::Error => e
          # wrap timeout errors in our custom exception type for consistency
          @exception = LazyInit::TimeoutError.new("Lazy initialization timed out after #{@timeout}s")
          raise @exception
        rescue StandardError => e
          # cache any other exceptions for consistent re-raising behavior
          @exception = e
          raise
        end
      end
    end
  end
end
