# frozen_string_literal: true

require 'timeout'

module LazyInit
  # optimized lazy value with ultra-fast hot path
  # eliminates exception checking from fast path for maximum performance
  class LazyValue
    def initialize(timeout: nil, &block)
      raise ArgumentError, 'Block is required' unless block

      @block = block
      @timeout = timeout
      @mutex = Mutex.new
      @computed = false
      @value = nil
      @exception = nil
    end

    # ultra-optimized value access with exception-free fast path
    # hot path: single instance variable check + return
    # cold path: full synchronization only when needed
    def value
      # ULTRA FAST PATH: no exception checking, just computed state and value
      # this should be nearly as fast as direct @var access
      return @value if @computed

      # SLOW PATH: computation needed or exception occurred
      compute_or_raise_exception
    end

    def computed?
      @computed && @exception.nil?
    end

    def reset!
      @mutex.synchronize do
        @computed = false
        @value = nil
        @exception = nil
      end
    end

    def exception?
      @mutex.synchronize { !@exception.nil? }
    end

    def exception
      @mutex.synchronize { @exception }
    end

    private

    # separated method to keep fast path minimal and focused
    # handles both computation and exception re-raising
    def compute_or_raise_exception
      @mutex.synchronize do
        # double-check: another thread might have computed while we waited
        return @value if @computed

        # check for cached exception
        raise @exception if @exception

        begin
          computed_value = if @timeout
                             Timeout.timeout(@timeout) do
                               @block.call
                             end
                           else
                             @block.call
                           end

          # atomic assignment: set value first, then mark as computed
          # this ensures @computed=true only when @value is valid
          @value = computed_value
          @computed = true

          computed_value
        rescue Timeout::Error => e
          @exception = LazyInit::TimeoutError.new("Lazy initialization timed out after #{@timeout}s")
          raise @exception
        rescue StandardError => e
          @exception = e
          raise
        end
      end
    end
  end
end