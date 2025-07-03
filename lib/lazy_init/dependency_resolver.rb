# frozen_string_literal: true

module LazyInit
  # Handles dependency resolution and circular dependency detection for lazy attributes.
  #
  # This resolver maintains a dependency graph and provides thread-safe resolution
  # with caching to avoid redundant dependency checking. It prevents circular
  # dependencies and optimizes performance through intelligent caching strategies.
  #
  # @example Basic usage
  #   resolver = DependencyResolver.new(MyClass)
  #   resolver.add_dependency(:database, [:config])
  #   resolver.resolve_dependencies(:database, instance)
  #
  # @since 0.1.0
  class DependencyResolver
    # Initialize a new dependency resolver for the given class.
    #
    # Sets up internal data structures for dependency tracking, resolution
    # caching, and thread safety mechanisms.
    #
    # @param target_class [Class] the class that owns the lazy attributes
    def initialize(target_class)
      @target_class = target_class
      @dependency_graph = {}
      @resolution_orders = {}
      @mutex = Mutex.new

      # per-instance caching to avoid redundant dependency resolution
      @instance_resolution_cache = {}
      @cache_mutex = Mutex.new
    end

    # Add a dependency relationship for an attribute.
    #
    # Records that the given attribute depends on other attributes and
    # pre-computes the resolution order for optimal performance.
    #
    # @param attribute [Symbol] the attribute that has dependencies
    # @param dependencies [Array<Symbol>, Symbol] the attributes it depends on
    # @return [void]
    def add_dependency(attribute, dependencies)
      @mutex.synchronize do
        @dependency_graph[attribute] = Array(dependencies)
        @resolution_orders[attribute] = compute_resolution_order(attribute)
        invalidate_dependent_orders(attribute)
      end
    end

    # Get the pre-computed resolution order for an attribute.
    #
    # @param attribute [Symbol] the attribute to get resolution order for
    # @return [Array<Symbol>, nil] ordered list of dependencies to resolve
    def resolution_order_for(attribute)
      @resolution_orders[attribute]
    end

    # Resolve all dependencies for an attribute on a specific instance.
    #
    # Uses intelligent caching to avoid redundant resolution and provides
    # thread-safe dependency resolution with circular dependency detection.
    # The resolution is cached per-instance to optimize repeated access.
    #
    # @param attribute [Symbol] the attribute whose dependencies to resolve
    # @param instance [Object] the instance to resolve dependencies on
    # @return [void]
    # @raise [DependencyError] if circular dependencies are detected
    def resolve_dependencies(attribute, instance)
      resolution_order = @resolution_orders[attribute]
      return unless resolution_order

      instance_key = instance.object_id
      cache_key = "#{instance_key}_#{attribute}"

      # fast path: if already resolved, skip everything
      return if dependency_resolved_cached?(cache_key)

      # prevent recursive mutex locking in nested dependency chains
      current_thread_resolving = Thread.current[:lazy_init_cache_resolving] ||= false

      if current_thread_resolving
        # we're already inside a resolution chain, skip caching to avoid deadlocks
        resolve_dependencies_direct(attribute, instance, resolution_order)
        return
      end

      # thread-safe cache update for top-level calls only
      @cache_mutex.synchronize do
        # double-check pattern after acquiring lock
        return if dependency_resolved_cached?(cache_key)

        # mark this thread as currently resolving to prevent recursion
        Thread.current[:lazy_init_cache_resolving] = true

        begin
          resolve_dependencies_direct(attribute, instance, resolution_order)
          mark_dependency_resolved(cache_key)
        ensure
          # always clean up thread state
          Thread.current[:lazy_init_cache_resolving] = false
        end
      end
    end

    private

    # Perform direct dependency resolution without caching overhead.
    #
    # This is the core resolution logic that handles circular dependency
    # detection and ensures dependencies are resolved in correct order.
    #
    # @param attribute [Symbol] the attribute being resolved
    # @param instance [Object] the target instance
    # @param resolution_order [Array<Symbol>] pre-computed dependency order
    # @return [void]
    # @raise [DependencyError] if circular dependencies detected
    def resolve_dependencies_direct(attribute, instance, resolution_order)
      # track resolution stack to detect circular dependencies
      resolution_stack = Thread.current[:lazy_init_resolution_stack] ||= []

      if resolution_stack.include?(attribute)
        raise LazyInit::DependencyError,
              "Circular dependency detected: #{resolution_stack.join(' -> ')} -> #{attribute}"
      end

      resolution_stack.push(attribute)

      begin
        # optimization: only resolve dependencies that aren't already computed
        unresolved_deps = resolution_order.reject do |dep|
          instance_computed?(instance, dep)
        end

        # trigger computation for unresolved dependencies
        unresolved_deps.each do |dep|
          instance.send(dep)
        end
      ensure
        # always clean up resolution stack
        resolution_stack.pop
        Thread.current[:lazy_init_resolution_stack] = nil if resolution_stack.empty?
      end
    end

    # Check if dependency resolution is already cached for this instance.
    #
    # @param cache_key [String] unique key for instance+attribute combination
    # @return [Boolean] true if dependencies already resolved
    def dependency_resolved_cached?(cache_key)
      @instance_resolution_cache[cache_key] == true
    end

    # Mark dependencies as resolved in the cache.
    #
    # Also handles cache cleanup to prevent memory leaks when cache grows too large.
    #
    # @param cache_key [String] unique key for instance+attribute combination
    # @return [void]
    def mark_dependency_resolved(cache_key)
      @instance_resolution_cache[cache_key] = true

      # prevent memory leaks by cleaning up oversized cache
      return unless @instance_resolution_cache.size > 1000

      cleanup_resolution_cache
    end

    # Clean up old cache entries to prevent unbounded memory growth.
    #
    # Removes the oldest 25% of cache entries when cache size exceeds limits.
    # This is a simple LRU-style cleanup strategy.
    #
    # @return [void]
    def cleanup_resolution_cache
      entries_to_remove = @instance_resolution_cache.size / 4
      keys_to_remove = @instance_resolution_cache.keys.first(entries_to_remove)
      keys_to_remove.each { |key| @instance_resolution_cache.delete(key) }
    end

    # Check if an attribute is already computed on the given instance.
    #
    # This checks for LazyValue-based attributes by looking for the lazy value
    # wrapper and checking its computed state.
    #
    # @param instance [Object] the instance to check
    # @param attribute [Symbol] the attribute to check
    # @return [Boolean] true if the attribute has been computed
    def instance_computed?(instance, attribute)
      lazy_value = instance.instance_variable_get("@#{attribute}_lazy_value")
      lazy_value&.computed?
    end

    # Compute the resolution order for a given attribute.
    #
    # Currently uses a simple approach that just returns the direct dependencies.
    # Future versions could implement more sophisticated dependency ordering.
    #
    # @param start_attribute [Symbol] the attribute to compute order for
    # @return [Array<Symbol>] ordered list of dependencies
    def compute_resolution_order(start_attribute)
      dependencies = @dependency_graph[start_attribute]
      return [] unless dependencies && dependencies.any?

      dependencies.dup
    end

    # Invalidate cached resolution orders when dependencies change.
    #
    # When an attribute's dependencies change, any attributes that depend on it
    # need their resolution orders recalculated.
    #
    # @param changed_attribute [Symbol] the attribute whose dependencies changed
    # @return [void]
    def invalidate_dependent_orders(changed_attribute)
      orders_to_update = {}

      @resolution_orders.each do |attribute, order|
        orders_to_update[attribute] = compute_resolution_order(attribute) if order.include?(changed_attribute)
      end

      orders_to_update.each do |attribute, new_order|
        @resolution_orders[attribute] = new_order
      end
    end
  end
end
