# frozen_string_literal: true

module LazyInit
  # Provides class-level methods for defining lazy attributes with various optimization strategies.
  #
  # This module is automatically extended when a class includes or extends LazyInit.
  # It analyzes attribute configuration and selects the most efficient implementation:
  # simple inline methods for basic cases, optimized dependency methods for single
  # dependencies, and full LazyValue wrappers for complex scenarios.
  #
  # The module generates three methods for each lazy attribute:
  # - `attribute_name` - the main accessor method
  # - `attribute_name_computed?` - predicate to check computation state
  # - `reset_attribute_name!` - method to reset and allow recomputation
  #
  # @example Basic lazy attribute
  #   class ApiClient
  #     extend LazyInit
  #
  #     lazy_attr_reader :connection do
  #       HTTPClient.new(api_url)
  #     end
  #   end
  #
  # @example Lazy attribute with dependencies
  #   class DatabaseService
  #     extend LazyInit
  #
  #     lazy_attr_reader :config do
  #       load_configuration
  #     end
  #
  #     lazy_attr_reader :connection, depends_on: [:config] do
  #       Database.connect(config.database_url)
  #     end
  #   end
  #
  # @since 0.1.0
  module ClassMethods
    # Set up necessary infrastructure when LazyInit is extended by a class.
    #
    # Initializes thread-safe mutex and dependency resolver for the target class.
    # This ensures each class has its own isolated dependency management.
    #
    # @param base [Class] the class being extended with LazyInit
    # @return [void]
    # @api private
    def self.extended(base)
      base.instance_variable_set(:@lazy_init_class_mutex, Mutex.new)
      base.instance_variable_set(:@dependency_resolver, DependencyResolver.new(base))
    end

    # Access the registry of all lazy initializers defined on this class.
    #
    # Used internally for introspection and debugging. Each entry contains
    # the configuration (block, timeout, dependencies) for a lazy attribute.
    #
    # @return [Hash<Symbol, Hash>] mapping of attribute names to their configuration
    def lazy_initializers
      @lazy_initializers ||= {}
    end

    # Access the dependency resolver for this class.
    #
    # Handles dependency graph management and resolution order computation.
    # Creates a new resolver if one doesn't exist.
    #
    # @return [DependencyResolver] the resolver instance for this class
    def dependency_resolver
      @dependency_resolver ||= DependencyResolver.new(self)
    end

    # Define a thread-safe lazy-initialized instance attribute.
    #
    # The attribute will be computed only once per instance when first accessed.
    # Subsequent calls return the cached value. The implementation is automatically
    # optimized based on complexity: simple cases use inline variables, single
    # dependencies use optimized resolution, complex cases use full LazyValue.
    #
    # @param name [Symbol, String] the attribute name
    # @param timeout [Numeric, nil] timeout in seconds for the computation
    # @param depends_on [Array<Symbol>, Symbol, nil] other attributes this depends on
    # @param block [Proc] the computation block
    # @return [void]
    # @raise [ArgumentError] if no block is provided
    # @raise [InvalidAttributeNameError] if the attribute name is invalid
    #
    # @example Simple lazy attribute
    #   lazy_attr_reader :expensive_data do
    #     fetch_from_external_api
    #   end
    #
    # @example With dependencies
    #   lazy_attr_reader :database, depends_on: [:config] do
    #     Database.connect(config.database_url)
    #   end
    #
    # @example With timeout protection
    #   lazy_attr_reader :slow_service, timeout: 10 do
    #     SlowExternalService.connect
    #   end
    def lazy_attr_reader(name, timeout: nil, depends_on: nil, &block)
      validate_attribute_name!(name)
      raise ArgumentError, 'Block is required' unless block

      # store configuration for introspection and debugging
      config = {
        block: block,
        timeout: timeout || LazyInit.configuration.default_timeout,
        depends_on: depends_on
      }
      lazy_initializers[name] = config

      # register dependencies with resolver if present
      dependency_resolver.add_dependency(name, depends_on) if depends_on

      # select optimal implementation strategy based on complexity
      if enhanced_simple_case?(timeout, depends_on)
        if simple_dependency_case?(depends_on)
          generate_simple_dependency_method(name, depends_on, block)
        else
          generate_simple_inline_method(name, block)
        end
      else
        generate_complex_lazyvalue_method(name, config)
      end

      # generate helper methods for all implementation types
      generate_predicate_method(name)
      generate_reset_method(name)
    end

    # Define a thread-safe lazy-initialized class variable shared across all instances.
    #
    # The variable will be computed only once per class when first accessed.
    # All instances share the same computed value. Class variables are always
    # implemented using LazyValue for full thread safety and feature support.
    #
    # @param name [Symbol, String] the class variable name
    # @param timeout [Numeric, nil] timeout in seconds for the computation
    # @param depends_on [Array<Symbol>, Symbol, nil] other attributes this depends on
    # @param block [Proc] the computation block
    # @return [void]
    # @raise [ArgumentError] if no block is provided
    # @raise [InvalidAttributeNameError] if the attribute name is invalid
    #
    # @example Shared connection pool
    #   lazy_class_variable :connection_pool do
    #     ConnectionPool.new(size: 20)
    #   end
    def lazy_class_variable(name, timeout: nil, depends_on: nil, &block)
      validate_attribute_name!(name)
      raise ArgumentError, 'Block is required' unless block

      class_variable_name = "@@#{name}_lazy_value"

      # register dependencies for class-level attributes too
      dependency_resolver.add_dependency(name, depends_on) if depends_on

      # cache configuration for use in generated methods
      cached_timeout = timeout
      cached_depends_on = depends_on
      cached_block = block

      # generate class-level accessor with full thread safety
      define_singleton_method(name) do
        @lazy_init_class_mutex.synchronize do
          return class_variable_get(class_variable_name).value if class_variable_defined?(class_variable_name)

          # resolve dependencies using temporary instance if needed
          if cached_depends_on
            temp_instance = begin
              new
            rescue StandardError
              # fallback for classes that can't be instantiated normally
              Object.new.tap { |obj| obj.extend(self) }
            end
            dependency_resolver.resolve_dependencies(name, temp_instance)
          end

          # create and store the lazy value wrapper
          lazy_value = LazyValue.new(timeout: cached_timeout, &cached_block)
          class_variable_set(class_variable_name, lazy_value)
          lazy_value.value
        end
      end

      # generate class-level predicate method
      define_singleton_method("#{name}_computed?") do
        if class_variable_defined?(class_variable_name)
          class_variable_get(class_variable_name).computed?
        else
          false
        end
      end

      # generate class-level reset method
      define_singleton_method("reset_#{name}!") do
        if class_variable_defined?(class_variable_name)
          lazy_value = class_variable_get(class_variable_name)
          lazy_value.reset!
          remove_class_variable(class_variable_name)
        end
      end

      # generate instance-level delegation methods for convenience
      define_method(name) { self.class.send(name) }
      define_method("#{name}_computed?") { self.class.send("#{name}_computed?") }
      define_method("reset_#{name}!") { self.class.send("reset_#{name}!") }
    end

    private

    # Determine if an attribute qualifies for simple optimization.
    #
    # Simple cases avoid LazyValue overhead by using direct instance variables.
    # This includes attributes with no timeout and either no dependencies or
    # a single simple dependency that can be inlined.
    #
    # @param timeout [Object] timeout configuration
    # @param depends_on [Object] dependency configuration
    # @return [Boolean] true if simple implementation should be used
    def enhanced_simple_case?(timeout, depends_on)
      # timeout requires LazyValue for proper handling
      return false unless timeout.nil?

      # categorize dependency complexity
      case depends_on
      when nil, []
        true # no dependencies are always simple
      when Array
        depends_on.size == 1 # single dependency can be optimized
      when Symbol, String
        true # single dependency in simple form
      else
        false
      end
    end

    # Check if dependencies qualify for simple dependency optimization.
    #
    # Single dependencies can use an optimized resolution strategy that
    # avoids the full dependency resolver overhead.
    #
    # @param depends_on [Object] dependency configuration
    # @return [Boolean] true if simple dependency method should be used
    def simple_dependency_case?(depends_on)
      return false if depends_on.nil? || depends_on.empty?

      deps = Array(depends_on)
      deps.size == 1 # any single dependency qualifies for optimization
    end

    # Generate an optimized method for attributes with single dependencies.
    #
    # This creates a method that uses inline variables for storage and
    # optimized dependency resolution that avoids LazyValue overhead.
    # Includes circular dependency detection and thread-safe error caching.
    #
    # @param name [Symbol] the attribute name
    # @param depends_on [Array, Symbol] the single dependency
    # @param block [Proc] the computation block
    # @return [void]
    def generate_simple_dependency_method(name, depends_on, block)
      dep_name = Array(depends_on).first
      computed_var = "@#{name}_computed"
      value_var = "@#{name}_value"
      exception_var = "@#{name}_exception"

      # cache references to avoid repeated lookups in generated method
      cached_block = block
      cached_dep_name = dep_name

      define_method(name) do
        # fast path: return cached result including cached errors
        if instance_variable_get(computed_var)
          stored_exception = instance_variable_get(exception_var)
          raise stored_exception if stored_exception

          return instance_variable_get(value_var)
        end

        # circular dependency protection using shared resolution stack
        resolution_stack = Thread.current[:lazy_init_resolution_stack] ||= []
        if resolution_stack.include?(name)
          circular_error = LazyInit::DependencyError.new(
            "Circular dependency detected: #{resolution_stack.join(' -> ')} -> #{name}"
          )

          # thread-safe error caching so all threads see the same error
          mutex = self.class.instance_variable_get(:@lazy_init_simple_mutex) || Mutex.new
          unless self.class.instance_variable_get(:@lazy_init_simple_mutex)
            self.class.instance_variable_set(:@lazy_init_simple_mutex, mutex)
          end

          mutex.synchronize do
            instance_variable_set(exception_var, circular_error)
            instance_variable_set(computed_var, true)
          end

          raise circular_error
        end

        # ensure we have a mutex for thread-safe computation
        mutex = self.class.instance_variable_get(:@lazy_init_simple_mutex)
        unless mutex
          mutex = Mutex.new
          self.class.instance_variable_set(:@lazy_init_simple_mutex, mutex)
        end

        # track this attribute in resolution stack
        resolution_stack.push(name)

        begin
          mutex.synchronize do
            # double-check pattern after acquiring lock
            if instance_variable_get(computed_var)
              stored_exception = instance_variable_get(exception_var)
              raise stored_exception if stored_exception

              return instance_variable_get(value_var)
            end

            begin
              # ensure dependency is computed first using optimized approach
              unless send("#{cached_dep_name}_computed?")
                # temporarily release lock to avoid deadlocks during dependency resolution
                mutex.unlock
                begin
                  send(cached_dep_name) # uses same shared resolution_stack for circular detection
                ensure
                  mutex.lock
                end

                # check if we got computed while lock was released
                if instance_variable_get(computed_var)
                  stored_exception = instance_variable_get(exception_var)
                  raise stored_exception if stored_exception

                  return instance_variable_get(value_var)
                end
              end

              # perform the actual computation with dependency available
              result = instance_eval(&cached_block)
              instance_variable_set(value_var, result)
              instance_variable_set(computed_var, true)
              result
            rescue StandardError => e
              # cache exceptions for consistent behavior across threads
              instance_variable_set(exception_var, e)
              instance_variable_set(computed_var, true)
              raise
            end
          end
        ensure
          # always clean up resolution stack to prevent leaks
          resolution_stack.pop
          Thread.current[:lazy_init_resolution_stack] = nil if resolution_stack.empty?
        end
      end
    end

    # Generate a simple inline method for attributes with no dependencies.
    #
    # Uses direct instance variables for maximum performance while maintaining
    # thread safety through mutex synchronization. This is the fastest
    # implementation strategy available.
    #
    # @param name [Symbol] the attribute name
    # @param block [Proc] the computation block
    # @return [void]
    def generate_simple_inline_method(name, block)
      computed_var = "@#{name}_computed"
      value_var = "@#{name}_value"
      exception_var = "@#{name}_exception"

      # cache block reference to avoid lookup in generated method
      cached_block = block

      define_method(name) do
        # fast path: return cached value immediately if available
        return instance_variable_get(value_var) if instance_variable_get(computed_var)

        # ensure we have a shared mutex for thread safety
        mutex = self.class.instance_variable_get(:@lazy_init_simple_mutex)
        unless mutex
          mutex = Mutex.new
          self.class.instance_variable_set(:@lazy_init_simple_mutex, mutex)
        end

        mutex.synchronize do
          # double-check pattern: another thread might have computed while we waited
          if instance_variable_get(computed_var)
            stored_exception = instance_variable_get(exception_var)
            raise stored_exception if stored_exception

            return instance_variable_get(value_var)
          end

          begin
            # perform computation and cache result
            result = instance_eval(&cached_block)
            instance_variable_set(value_var, result)
            instance_variable_set(computed_var, true)
            result
          rescue StandardError => e
            # cache exceptions to ensure consistent error behavior
            instance_variable_set(exception_var, e)
            instance_variable_set(computed_var, true)
            raise
          end
        end
      end
    end

    # Generate a method using full LazyValue for complex scenarios.
    #
    # This handles timeouts, complex dependencies, and other advanced features
    # that require the full LazyValue implementation. Used when simple
    # optimizations aren't applicable.
    #
    # @param name [Symbol] the attribute name
    # @param config [Hash] the attribute configuration
    # @return [void]
    def generate_complex_lazyvalue_method(name, config)
      # cache configuration to avoid hash lookups in generated method
      cached_timeout = config[:timeout]
      cached_depends_on = config[:depends_on]
      cached_block = config[:block]

      define_method(name) do
        # resolve dependencies using full dependency resolver if needed
        self.class.dependency_resolver.resolve_dependencies(name, self) if cached_depends_on

        # lazy creation of LazyValue wrapper
        ivar_name = "@#{name}_lazy_value"
        lazy_value = instance_variable_get(ivar_name) if instance_variable_defined?(ivar_name)

        unless lazy_value
          lazy_value = LazyValue.new(timeout: cached_timeout) do
            instance_eval(&cached_block)
          end
          instance_variable_set(ivar_name, lazy_value)
        end

        lazy_value.value
      end
    end

    # Generate predicate method to check if attribute has been computed.
    #
    # Handles both simple (inline variables) and complex (LazyValue) cases.
    # Returns false for exceptions to maintain consistent behavior.
    #
    # @param name [Symbol] the attribute name
    # @return [void]
    def generate_predicate_method(name)
      define_method("#{name}_computed?") do
        # check simple implementation first (most common after optimization)
        computed_var = "@#{name}_computed"
        exception_var = "@#{name}_exception"

        if instance_variable_defined?(computed_var)
          # simple implementation: computed but not if there's a cached exception
          return instance_variable_get(computed_var) && !instance_variable_get(exception_var)
        end

        # check complex implementation (LazyValue wrapper)
        lazy_var = "@#{name}_lazy_value"
        if instance_variable_defined?(lazy_var)
          lazy_value = instance_variable_get(lazy_var)
          return lazy_value&.computed? || false
        end

        # not computed yet
        false
      end
    end

    # Generate reset method to clear computed state and allow recomputation.
    #
    # Handles both simple and complex implementations, ensuring proper
    # cleanup of all associated state including cached exceptions.
    #
    # @param name [Symbol] the attribute name
    # @return [void]
    def generate_reset_method(name)
      define_method("reset_#{name}!") do
        # handle simple implementation reset
        computed_var = "@#{name}_computed"
        value_var = "@#{name}_value"
        exception_var = "@#{name}_exception"

        if instance_variable_defined?(computed_var)
          # use mutex if available for thread safety during reset
          mutex = self.class.instance_variable_get(:@lazy_init_simple_mutex)
          if mutex
            mutex.synchronize do
              instance_variable_set(computed_var, false)
              remove_instance_variable(value_var) if instance_variable_defined?(value_var)
              remove_instance_variable(exception_var) if instance_variable_defined?(exception_var)
            end
          else
            # no mutex means no concurrent access, safe to reset directly
            instance_variable_set(computed_var, false)
            remove_instance_variable(value_var) if instance_variable_defined?(value_var)
            remove_instance_variable(exception_var) if instance_variable_defined?(exception_var)
          end
          return
        end

        # handle complex implementation reset (LazyValue)
        lazy_var = "@#{name}_lazy_value"
        if instance_variable_defined?(lazy_var)
          lazy_value = instance_variable_get(lazy_var)
          lazy_value&.reset!
          remove_instance_variable(lazy_var)
        end
      end
    end

    # Validate that the attribute name is suitable for method generation.
    #
    # Ensures the name follows Ruby method naming conventions and won't
    # cause issues when used to generate accessor methods.
    #
    # @param name [Object] the proposed attribute name
    # @return [void]
    # @raise [InvalidAttributeNameError] if the name is invalid
    def validate_attribute_name!(name)
      raise InvalidAttributeNameError, 'Attribute name cannot be nil' if name.nil?
      raise InvalidAttributeNameError, 'Attribute name cannot be empty' if name.to_s.strip.empty?

      unless name.is_a?(Symbol) || name.is_a?(String)
        raise InvalidAttributeNameError, 'Attribute name must be a symbol or string'
      end

      name_str = name.to_s
      return if name_str.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*[?!]?\z/)

      raise InvalidAttributeNameError, "Invalid attribute name: #{name_str}"
    end
  end
end
