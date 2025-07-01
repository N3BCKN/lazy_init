# frozen_string_literal: true

require 'set'

module LazyInit
  # Manages dependency resolution for lazy attributes.
  #
  # This class handles the computation order of lazy attributes that depend on other
  # lazy attributes. It ensures dependencies are resolved in the correct order and
  # provides efficient resolution using pre-computed dependency chains.
  #
  # @example Dependency chain
  #   # Given these definitions:
  #   lazy_attr_reader :config do
  #     load_configuration
  #   end
  #   
  #   lazy_attr_reader :database, depends_on: [:config] do
  #     Database.connect(config.database_url)
  #   end
  #   
  #   # When accessing :database, the resolver ensures :config is computed first
  #
  # @api private
  # @since 0.1.0
  class DependencyResolver
    # Initializes a new dependency resolver for the given class.
    #
    # @param target_class [Class] the class this resolver manages dependencies for
    def initialize(target_class)
      @target_class = target_class
      @dependency_graph = {}
      @resolution_orders = {}
      @mutex = Mutex.new
    end

    # Adds a dependency relationship for an attribute.
    #
    # This method registers that the given attribute depends on other attributes
    # and pre-computes the resolution order for efficient runtime access.
    #
    # @param attribute [Symbol] the attribute that has dependencies
    # @param dependencies [Array<Symbol>, Symbol] the attributes this depends on
    # @return [void]
    # @raise [DependencyError] if a circular dependency is detected
    #
    # @example Adding dependencies
    #   resolver.add_dependency(:database, [:config])
    #   resolver.add_dependency(:api_client, [:config, :database])
    def add_dependency(attribute, dependencies)
      @mutex.synchronize do
        @dependency_graph[attribute] = Array(dependencies)
        @resolution_orders[attribute] = compute_resolution_order(attribute)
        invalidate_dependent_orders(attribute)
      end
    end

    # Resolves dependencies for an attribute by ensuring all dependencies are computed.
    #
    # This method checks each dependency and triggers its computation if it hasn't
    # been computed yet. It uses the pre-computed resolution order for efficiency.
    #
    # @param attribute [Symbol] the attribute whose dependencies should be resolved
    # @param instance [Object] the instance on which to resolve dependencies
    # @return [void]
    #
    # @example Resolving dependencies
    #   # This will ensure :config is computed before :database
    #   resolver.resolve_dependencies(:database, my_instance)
    def resolve_dependencies(attribute, instance)
      resolution_order = @resolution_orders[attribute]
      return unless resolution_order

      # Add runtime circular dependency protection
      resolution_stack = Thread.current[:lazy_init_resolution_stack] ||= []
      
      if resolution_stack.include?(attribute)
        raise LazyInit::DependencyError, "Circular dependency detected: #{resolution_stack.join(' -> ')} -> #{attribute}"
      end
      
      resolution_stack.push(attribute)
      
      begin
        resolution_order.each do |dep|
          next if instance_computed?(instance, dep)
          instance.send(dep)
        end
      ensure
        resolution_stack.pop
        Thread.current[:lazy_init_resolution_stack] = nil if resolution_stack.empty?
      end
    end

    # Returns the resolution order for the given attribute.
    #
    # This is primarily used for introspection and debugging purposes.
    #
    # @param attribute [Symbol] the attribute to get resolution order for
    # @return [Array<Symbol>, nil] the ordered list of dependencies, or nil if none
    #
    # @example Getting resolution order
    #   resolver.resolution_order_for(:database)  #=> [:config]
    #   resolver.resolution_order_for(:api_client) #=> [:config, :database]
    def resolution_order_for(attribute)
      @resolution_orders[attribute]
    end

    private

    # Checks if an attribute has been computed on the given instance.
    #
    # @param instance [Object] the instance to check
    # @param attribute [Symbol] the attribute to check
    # @return [Boolean] true if the attribute has been computed
    def instance_computed?(instance, attribute)
      lazy_value = instance.instance_variable_get("@#{attribute}_lazy_value")
      lazy_value&.computed?
    end

    # Computes the resolution order for an attribute.
    #
    # Currently returns only direct dependencies. Each dependency will handle
    # its own sub-dependencies when accessed, avoiding redundant computation.
    #
    # @param start_attribute [Symbol] the attribute to compute order for
    # @return [Array<Symbol>] the ordered list of direct dependencies
    def compute_resolution_order(start_attribute)
      dependencies = @dependency_graph[start_attribute]
      return [] unless dependencies && dependencies.any?

      dependencies.dup
    end

    # Collects all attributes in a dependency subgraph.
    #
    # This method traverses the dependency graph starting from the given attribute
    # and returns all attributes that are part of its dependency chain.
    #
    # @param start_attribute [Symbol] the starting attribute
    # @return [Array<Symbol>] all attributes in the dependency subgraph
    # @note This method is kept for backward compatibility but not currently used
    def collect_dependency_subgraph(start_attribute)
      visited = Set.new
      stack = [start_attribute]
      
      while stack.any?
        current = stack.pop
        next if visited.include?(current)
        
        visited.add(current)
        deps = @dependency_graph[current] || []
        stack.concat(deps)
      end
      
      visited.to_a
    end

    # Invalidates cached resolution orders that depend on the changed attribute.
    #
    # When an attribute's dependencies change, this method finds all other attributes
    # that might be affected and recomputes their resolution orders.
    #
    # @param changed_attribute [Symbol] the attribute whose dependencies changed
    # @return [void]
    def invalidate_dependent_orders(changed_attribute)
      # FIXED: Create a copy of the hash to avoid modification during iteration
      orders_to_update = {}
      
      @resolution_orders.each do |attribute, order|
        if order.include?(changed_attribute)
          orders_to_update[attribute] = compute_resolution_order(attribute)
        end
      end
      
      # Now safely update the resolution orders
      orders_to_update.each do |attribute, new_order|
        @resolution_orders[attribute] = new_order
      end
    end
  end
end