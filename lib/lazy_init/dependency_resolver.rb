# frozen_string_literal: true

require 'set'

module LazyInit
  # Thread-safe dependency resolver with automatic circular dependency detection.
  #
  # Manages dependency graphs for lazy attributes and ensures proper resolution
  # order while preventing infinite loops from circular dependencies.
  #
  # @example Dependency resolution
  #   # Given: database depends on [:config], api depends on [:database, :config]
  #   # Calling api triggers: config → database → api
  #
  # @since 0.1.0
  class DependencyResolver
    # Creates a new dependency resolver for the target class.
    #
    # @param target_class [Class] the class that owns the lazy attributes
    def initialize(target_class)
      @target_class = target_class
      @dependency_graph = {}
      @mutex = Mutex.new
    end

    # Registers dependencies for a lazy attribute.
    #
    # @param attribute [Symbol] the attribute name
    # @param dependencies [Array<Symbol>, Symbol] attribute dependencies
    # @return [void]
    def add_dependency(attribute, dependencies)
      @mutex.synchronize do
        @dependency_graph[attribute] = Array(dependencies)
      end
    end

    # Resolves dependencies for an attribute in the correct order.
    #
    # Creates a fresh resolution context to prevent thread interference
    # and ensures all dependencies are computed before the target attribute.
    #
    # @param attribute [Symbol] the attribute to resolve dependencies for
    # @param instance [Object] the instance to resolve dependencies on
    # @raise [DependencyError] if circular dependencies are detected
    # @return [void]
    #
    # @example Resolving complex dependencies
    #   resolver.resolve_dependencies(:api_client, instance)
    #   # Automatically resolves: config → database → api_client
    def resolve_dependencies(attribute, instance)
      # Create fresh resolution context for this call
      context = ResolutionContext.new(instance)
      context.resolve(attribute, @dependency_graph)
    end

    # Per-resolution state container to prevent thread conflicts.
    #
    # Each dependency resolution gets its own context to track resolved
    # attributes and detect circular dependencies safely.
    class ResolutionContext
      # @param instance [Object] the instance to resolve dependencies on
      def initialize(instance)
        @instance = instance
        @resolved = Set.new
        @resolving = Set.new
        @resolution_stack = []
      end

      # @param attribute [Symbol] the attribute to resolve
      # @param dependency_graph [Hash] the complete dependency graph
      def resolve(attribute, dependency_graph)
        resolve_recursive(attribute, dependency_graph)
      end

      private

      def resolve_recursive(attribute, dependency_graph)
        # Check for circular dependencies
        if @resolving.include?(attribute)
          cycle_path = @resolution_stack + [attribute]
          raise DependencyError, "Circular dependency detected: #{cycle_path.join(' -> ')}"
        end

        return if @resolved.include?(attribute)

        # Mark as currently resolving
        @resolving.add(attribute)
        @resolution_stack.push(attribute)

        begin
          dependencies = dependency_graph[attribute] || []

          # Resolve all dependencies first
          dependencies.each do |dep|
            resolve_recursive(dep, dependency_graph)

            # Trigger computation of dependency if not computed
            @instance.send(dep) unless @instance.send("#{dep}_computed?")
          end

          # Mark as resolved
          @resolved.add(attribute)
        ensure
          # Clean up resolution state
          @resolving.delete(attribute)
          @resolution_stack.pop
        end
      end
    end
  end
end
