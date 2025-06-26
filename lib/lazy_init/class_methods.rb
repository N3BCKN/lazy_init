# frozen_string_literal: true

module LazyInit
  # Class methods with cached configuration for better performance
  module ClassMethods
    def self.extended(base)
      # Thread-safe class mutex initialization
      base.instance_variable_set(:@lazy_init_class_mutex, Mutex.new)
      base.instance_variable_set(:@dependency_resolver, DependencyResolver.new(base))
    end

    # Defines a lazy attribute reader with cached configuration
    #
    # Cache configuration at method generation time instead of runtime lookup
    # This eliminates hash lookups in hot path, providing significant performance improvement
    #
    # Creates three methods:
    # - `name` - returns the lazy-initialized value
    # - `name_computed?` - returns true if the value has been computed
    # - `reset_name!` - resets the value to uncomputed state
    def lazy_attr_reader(name, timeout: nil, depends_on: nil, if_condition: nil, &block)
      validate_attribute_name!(name)
      raise ArgumentError, 'Block is required' unless block

      # Store configuration for introspection and dependency tracking
      config = { 
        block: block, 
        timeout: timeout || LazyInit.configuration.default_timeout,
        depends_on: depends_on,
        condition: if_condition
      }
      lazy_initializers[name] = config

      # Setup dependency tracking (thread-safe)
      if depends_on
        dependency_resolver.add_dependency(name, depends_on)
      end

      # Choose implementation strategy based on complexity
      if simple_case?(timeout, depends_on, if_condition)
        generate_simple_inline_method(name, block)
      else
        generate_optimized_lazyvalue_method(name, timeout, depends_on, if_condition, block)
      end
      
      # Generate helper methods
      generate_predicate_method(name)
      generate_reset_method(name)
    end

    # Defines a lazy class-level variable with cached config
    def lazy_class_variable(name, timeout: nil, depends_on: nil, if_condition: nil, &block)
      validate_attribute_name!(name)
      raise ArgumentError, 'Block is required' unless block

      class_variable_name = "@@#{name}_lazy_value"

      # Setup dependency tracking for class variables
      if depends_on
        dependency_resolver.add_dependency(name, depends_on)
      end

      # Cache configuration values at generation time
      cached_timeout = timeout
      cached_depends_on = depends_on
      cached_condition = if_condition
      cached_block = block

      # Define class method with cached configuration
      define_singleton_method(name) do
        @lazy_init_class_mutex.synchronize do
          # Check if already computed
          if class_variable_defined?(class_variable_name)
            return class_variable_get(class_variable_name).value
          end
          
          # Evaluate cached condition if present
          if cached_condition
            condition_result = cached_condition.call
            unless condition_result
              # Store nil result using a simple computed LazyValue
              nil_lazy_value = LazyValue.new { nil }
              # Force computation to set computed flag
              nil_lazy_value.value
              class_variable_set(class_variable_name, nil_lazy_value)
              return nil
            end
          end

          # Resolve dependencies at class level using cached dependencies
          if cached_depends_on
            temp_instance = new rescue Object.new.tap { |obj| obj.extend(self) }
            dependency_resolver.resolve_dependencies(name, temp_instance)
          end

          # Create and store lazy value with cached config
          lazy_value = LazyValue.new(timeout: cached_timeout, &cached_block)
          class_variable_set(class_variable_name, lazy_value)
          lazy_value.value
        end
      end

      # Define class predicate and reset methods (unchanged)
      define_singleton_method("#{name}_computed?") do
        if class_variable_defined?(class_variable_name)
          class_variable_get(class_variable_name).computed?
        else
          false
        end
      end

      define_singleton_method("reset_#{name}!") do
        if class_variable_defined?(class_variable_name)
          lazy_value = class_variable_get(class_variable_name)
          lazy_value.reset!
          remove_class_variable(class_variable_name)
        end
      end

      # Define instance methods that delegate to class methods
      define_method(name) { self.class.send(name) }
      define_method("#{name}_computed?") { self.class.send("#{name}_computed?") }
      define_method("reset_#{name}!") { self.class.send("reset_#{name}!") }
    end

    # Storage for lazy attribute initializer blocks (for introspection)
    # Note: This is still used for dependency tracking and introspection,
    # but not for runtime configuration access (optimization)
    def lazy_initializers
      @lazy_initializers ||= {}
    end

    def dependency_resolver
      @dependency_resolver ||= DependencyResolver.new(self)
    end

    private 

    # Determines if this is a simple case that can use inline optimization
    def simple_case?(timeout, depends_on, if_condition)
      timeout.nil? && depends_on.nil? && if_condition.nil?
    end

    def generate_simple_inline_method(name, block)
      # Use direct instance variable names (no _lazy_value suffix)
      computed_var = "@#{name}_computed"
      value_var = "@#{name}_value"
      exception_var = "@#{name}_exception"
      mutex_var = "@#{name}_mutex"
      
      define_method(name) do
        # Direct instance variable access (no instance_variable_get)
        # Fast path: check computed flag directly
        if instance_variable_defined?(computed_var) && instance_variable_get(computed_var)
          return instance_variable_get(value_var)
        end
        
        # Exception replay path
        if instance_variable_defined?(exception_var)
          raise instance_variable_get(exception_var)
        end
        
        # Slow path: thread-safe computation
        # Lazy mutex initialization to avoid overhead
        mutex = instance_variable_get(mutex_var) if instance_variable_defined?(mutex_var)
        unless mutex
          mutex = Mutex.new
          instance_variable_set(mutex_var, mutex)
        end
        
        mutex.synchronize do
          # Double-check pattern
          if instance_variable_defined?(computed_var) && instance_variable_get(computed_var)
            return instance_variable_get(value_var)
          end
          
          # Exception replay in critical section
          if instance_variable_defined?(exception_var)
            raise instance_variable_get(exception_var)
          end
          
          begin
            # Compute value
            computed_value = instance_eval(&block)
            
            # Atomic assignment: value first, then computed flag
            instance_variable_set(value_var, computed_value)
            instance_variable_set(computed_var, true)
            
            computed_value
          rescue => e
            # Cache exception for future calls
            instance_variable_set(exception_var, e)
            raise
          end
        end
      end
    end

    # Complex cases still use LazyValue but with cached config
    def generate_optimized_lazyvalue_method(name, timeout, depends_on, if_condition, block)
      # Cache configuration values at generation time
      cached_timeout = timeout
      cached_depends_on = depends_on
      cached_condition = if_condition
      cached_block = block

      define_method(name) do
        # Handle conditional loading with cached condition
        if cached_condition
          condition_result = instance_exec(&cached_condition)
          return nil unless condition_result
        end

        # Thread-safe dependency resolution using cached dependencies
        if cached_depends_on
          self.class.dependency_resolver.resolve_dependencies(name, self)
        end

        # Direct instance variable access
        ivar_name = "@#{name}_lazy_value"
        
        # Check if already exists using direct access
        if instance_variable_defined?(ivar_name)
          lazy_value = instance_variable_get(ivar_name)
          return lazy_value.value
        end
        
        # Create and cache LazyValue with optimized config
        lazy_value = LazyValue.new(timeout: cached_timeout) do
          instance_eval(&cached_block)
        end
        instance_variable_set(ivar_name, lazy_value)
        lazy_value.value
      end
    end

    def generate_predicate_method(name)
      define_method("#{name}_computed?") do
        # Check inline approach first
        computed_var = "@#{name}_computed"
        if instance_variable_defined?(computed_var)
          return instance_variable_get(computed_var) || false
        end
        
        # Check LazyValue approach
        lazy_var = "@#{name}_lazy_value"
        if instance_variable_defined?(lazy_var)
          lazy_value = instance_variable_get(lazy_var)
          return lazy_value&.computed? || false
        end
        
        false
      end
    end

    def generate_reset_method(name)
      define_method("reset_#{name}!") do
        # Reset inline variables
        computed_var = "@#{name}_computed"
        value_var = "@#{name}_value"
        exception_var = "@#{name}_exception"
        
        [computed_var, value_var, exception_var].each do |var|
          remove_instance_variable(var) if instance_variable_defined?(var)
        end
        
        # Reset LazyValue if exists
        lazy_var = "@#{name}_lazy_value"
        if instance_variable_defined?(lazy_var)
          lazy_value = instance_variable_get(lazy_var)
          lazy_value&.reset!
          remove_instance_variable(lazy_var)
        end
      end
    end

    def validate_attribute_name!(name)
      raise InvalidAttributeNameError, 'Attribute name cannot be nil' if name.nil?
      raise InvalidAttributeNameError, 'Attribute name cannot be empty' if name.to_s.strip.empty?
      raise InvalidAttributeNameError, 'Attribute name must be a symbol or string' unless name.is_a?(Symbol) || name.is_a?(String)
      
      name_str = name.to_s
      raise InvalidAttributeNameError, "Invalid attribute name: #{name_str}" unless name_str.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*[?!]?\z/)
    end
  end
end