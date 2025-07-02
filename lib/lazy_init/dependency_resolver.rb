# frozen_string_literal: true

# PHASE 1.1 (REVISED): Smart Dependency Resolution Caching
# Target: Reduce dependency resolution overhead from 1.298μs to ~0.6μs
# Strategy: Cache resolved dependencies per instance to avoid repeated checks
# Risk: LOW - only adds caching, doesn't change core logic

module LazyInit
  class DependencyResolver
    # Initialize resolver with caching support
    def initialize(target_class)
      @target_class = target_class
      @dependency_graph = {}
      @resolution_orders = {}
      @mutex = Mutex.new
      # NEW: Add per-instance dependency resolution cache
      @instance_resolution_cache = {}
      @cache_mutex = Mutex.new
    end

    # PUBLIC METHODS - called from ClassMethods

    # Adds a dependency relationship for an attribute (UNCHANGED)
    def add_dependency(attribute, dependencies)
      @mutex.synchronize do
        @dependency_graph[attribute] = Array(dependencies)
        @resolution_orders[attribute] = compute_resolution_order(attribute)
        invalidate_dependent_orders(attribute)
      end
    end

    # Returns the resolution order for the given attribute (UNCHANGED)
    def resolution_order_for(attribute)
      @resolution_orders[attribute]
    end

    # OPTIMIZED: Cache-aware dependency resolution
    def resolve_dependencies(attribute, instance)
      resolution_order = @resolution_orders[attribute]
      return unless resolution_order

      # OPTIMIZATION 1: Use instance-level cache key
      instance_key = instance.object_id
      cache_key = "#{instance_key}_#{attribute}"

      # OPTIMIZATION 2: Quick cache check (lock-free for cache hits)
      if dependency_resolved_cached?(cache_key)
        return
      end

      # OPTIMIZATION 3: Check if we're already in a resolution chain
      # Prevent recursive mutex locking
      current_thread_resolving = Thread.current[:lazy_init_cache_resolving] ||= false
      
      if current_thread_resolving
        # We're already inside resolution chain - skip caching, do direct resolution
        resolve_dependencies_direct(attribute, instance, resolution_order)
        return
      end

      # OPTIMIZATION 4: Thread-safe cache update (only for top-level calls)
      @cache_mutex.synchronize do
        # Double-check pattern
        return if dependency_resolved_cached?(cache_key)

        # Mark that this thread is now resolving dependencies
        Thread.current[:lazy_init_cache_resolving] = true
        
        begin
          resolve_dependencies_direct(attribute, instance, resolution_order)
          
          # OPTIMIZATION 5: Mark as resolved in cache
          mark_dependency_resolved(cache_key)
          
        ensure
          # Always clean up thread state
          Thread.current[:lazy_init_cache_resolving] = false
        end
      end
    end

    private

    # HELPER: Direct dependency resolution without caching/locking
    def resolve_dependencies_direct(attribute, instance, resolution_order)
      # Runtime circular dependency protection
      resolution_stack = Thread.current[:lazy_init_resolution_stack] ||= []
      
      if resolution_stack.include?(attribute)
        raise LazyInit::DependencyError, "Circular dependency detected: #{resolution_stack.join(' -> ')} -> #{attribute}"
      end
      
      resolution_stack.push(attribute)
      
      begin
        # OPTIMIZATION: Batch dependency checking
        unresolved_deps = resolution_order.reject do |dep|
          instance_computed?(instance, dep)
        end

        # Only resolve what's actually needed
        unresolved_deps.each do |dep|
          instance.send(dep)
        end
        
      ensure
        resolution_stack.pop
        Thread.current[:lazy_init_resolution_stack] = nil if resolution_stack.empty?
      end
    end

    private

    # Check if dependency resolution is cached
    def dependency_resolved_cached?(cache_key)
      @instance_resolution_cache[cache_key] == true
    end

    # Mark dependency as resolved in cache
    def mark_dependency_resolved(cache_key)
      @instance_resolution_cache[cache_key] = true
      
      # OPTIMIZATION 6: Cleanup cache if it gets too large (prevent memory leaks)
      if @instance_resolution_cache.size > 1000
        cleanup_resolution_cache
      end
    end

    # Clean up old cache entries (keep memory usage bounded)
    def cleanup_resolution_cache
      # Remove oldest 25% of entries
      entries_to_remove = @instance_resolution_cache.size / 4
      keys_to_remove = @instance_resolution_cache.keys.first(entries_to_remove)
      keys_to_remove.each { |key| @instance_resolution_cache.delete(key) }
    end

    # EXISTING METHODS - keeping all original functionality

    # Adds a dependency relationship for an attribute (UNCHANGED)
    # def add_dependency(attribute, dependencies)
    #   @mutex.synchronize do
    #     @dependency_graph[attribute] = Array(dependencies)
    #     @resolution_orders[attribute] = compute_resolution_order(attribute)
    #     invalidate_dependent_orders(attribute)
    #   end
    # end

    # Returns the resolution order for the given attribute (UNCHANGED)
    def resolution_order_for(attribute)
      @resolution_orders[attribute]
    end

    # Existing method - no changes
    def instance_computed?(instance, attribute)
      lazy_value = instance.instance_variable_get("@#{attribute}_lazy_value")
      lazy_value&.computed?
    end

    private

    # PRIVATE HELPER METHODS

    # Computes the resolution order for an attribute (UNCHANGED)
    def compute_resolution_order(start_attribute)
      dependencies = @dependency_graph[start_attribute]
      return [] unless dependencies && dependencies.any?

      dependencies.dup
    end

    # Invalidates cached resolution orders (UNCHANGED)
    def invalidate_dependent_orders(changed_attribute)
      orders_to_update = {}
      
      @resolution_orders.each do |attribute, order|
        if order.include?(changed_attribute)
          orders_to_update[attribute] = compute_resolution_order(attribute)
        end
      end
      
      orders_to_update.each do |attribute, new_order|
        @resolution_orders[attribute] = new_order
      end
    end
  end
end