# frozen_string_literal: true

module LazyInit  
  module ClassMethods
    def self.extended(base)
      base.instance_variable_set(:@lazy_init_class_mutex, Mutex.new)
      base.instance_variable_set(:@dependency_resolver, DependencyResolver.new(base))
    end

    def lazy_attr_reader(name, timeout: nil, depends_on: nil, if_condition: nil, &block)
      validate_attribute_name!(name)
      raise ArgumentError, 'Block is required' unless block

      # Store configuration for introspection (unchanged)
      config = { 
        block: block, 
        timeout: timeout || LazyInit.configuration.default_timeout,
        depends_on: depends_on,
        condition: if_condition
      }
      lazy_initializers[name] = config

      # Setup dependency tracking (unchanged)
      if depends_on
        dependency_resolver.add_dependency(name, depends_on)
      end

      if simple_case?(timeout, depends_on, if_condition)
        generate_simple_inline_method(name, block)
      else
        generate_complex_lazyvalue_method(name, config)
      end
      
      generate_predicate_method(name)
      generate_reset_method(name)
    end

    # Rest of the methods unchanged...
    def lazy_class_variable(name, timeout: nil, depends_on: nil, if_condition: nil, &block)
      validate_attribute_name!(name)
      raise ArgumentError, 'Block is required' unless block

      class_variable_name = "@@#{name}_lazy_value"

      if depends_on
        dependency_resolver.add_dependency(name, depends_on)
      end

      # Cache configuration to avoid runtime lookups
      cached_timeout = timeout
      cached_depends_on = depends_on
      cached_condition = if_condition
      cached_block = block

      define_singleton_method(name) do
        @lazy_init_class_mutex.synchronize do
          if class_variable_defined?(class_variable_name)
            return class_variable_get(class_variable_name).value
          end
          
          if cached_condition
            condition_result = cached_condition.call
            unless condition_result
              nil_lazy_value = LazyValue.new { nil }
              nil_lazy_value.value
              class_variable_set(class_variable_name, nil_lazy_value)
              return nil
            end
          end

          if cached_depends_on
            temp_instance = new rescue Object.new.tap { |obj| obj.extend(self) }
            dependency_resolver.resolve_dependencies(name, temp_instance)
          end

          lazy_value = LazyValue.new(timeout: cached_timeout, &cached_block)
          class_variable_set(class_variable_name, lazy_value)
          lazy_value.value
        end
      end

      # Helper methods (unchanged)
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

      # Delegate instance methods (unchanged)
      define_method(name) { self.class.send(name) }
      define_method("#{name}_computed?") { self.class.send("#{name}_computed?") }
      define_method("reset_#{name}!") { self.class.send("reset_#{name}!") }
    end

    def lazy_initializers
      @lazy_initializers ||= {}
    end

    def dependency_resolver
      @dependency_resolver ||= DependencyResolver.new(self)
    end

    private

    # Determine if we can use simple inline implementation
    def simple_case?(timeout, depends_on, if_condition)
      # Simple case: no timeout, no dependencies, no conditions
      timeout.nil? && depends_on.nil? && if_condition.nil?
    end

    # Ultra-fast inline implementation for simple cases
    # This should get us close to manual ||= performance (~2-3x overhead)
    def generate_simple_inline_method(name, block)
      computed_var = "@#{name}_computed"
      value_var = "@#{name}_value"
      mutex_var = "@#{name}_mutex"
      exception_var = "@#{name}_exception"
      
      # Cache the block to avoid repeated lookups
      cached_block = block

      define_method(name) do
        # FAST PATH: Direct instance variable check (fastest possible)
        if instance_variable_get(computed_var)
          stored_exception = instance_variable_get(exception_var)
          raise stored_exception if stored_exception
          return instance_variable_get(value_var)
        end

        # SLOW PATH: Need to compute
        # Lazy mutex allocation to save memory
        mutex = instance_variable_get(mutex_var)
        unless mutex
          mutex = Mutex.new
          instance_variable_set(mutex_var, mutex)
        end

        mutex.synchronize do
          # Double-check pattern
          if instance_variable_get(computed_var)
            stored_exception = instance_variable_get(exception_var)
            raise stored_exception if stored_exception
            return instance_variable_get(value_var)
          end

          # Check if exception was stored by another thread
          stored_exception = instance_variable_get(exception_var)
          raise stored_exception if stored_exception

          begin
            # Direct block execution (no LazyValue wrapper)
            result = instance_eval(&cached_block)
            
            # Atomic assignment - value first, then computed flag
            instance_variable_set(value_var, result)
            instance_variable_set(computed_var, true)
            result
          rescue StandardError => e
            # Store exception and mark as computed to prevent re-execution
            instance_variable_set(exception_var, e)
            instance_variable_set(computed_var, true)
            raise
          end
        end
      end
    end

    # Keep LazyValue for complex cases but use optimized dependency resolution
    def generate_complex_lazyvalue_method(name, config)
      # Cache configuration values at method generation time
      cached_timeout = config[:timeout]
      cached_depends_on = config[:depends_on]
      cached_condition = config[:condition]
      cached_block = config[:block]

      define_method(name) do
        # Conditional loading check
        if cached_condition
          condition_result = instance_exec(&cached_condition)
          return nil unless condition_result
        end

        # Optimized dependency resolution (from FAZA 1)
        if cached_depends_on
          self.class.dependency_resolver.resolve_dependencies(name, self)
        end

        # LazyValue creation and access for complex cases
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

    # Unified predicate method that works with both implementations
    def generate_predicate_method(name)
      define_method("#{name}_computed?") do
        # Check simple inline implementation first
        computed_var = "@#{name}_computed"
        exception_var = "@#{name}_exception"
        
        if instance_variable_defined?(computed_var)
          # For simple implementation: computed AND no exception
          return instance_variable_get(computed_var) && !instance_variable_get(exception_var)
        end
        
        # Fallback to LazyValue implementation
        lazy_var = "@#{name}_lazy_value"
        if instance_variable_defined?(lazy_var)
          lazy_value = instance_variable_get(lazy_var)
          return lazy_value&.computed? || false
        end
        
        false
      end
    end

    # Unified reset method that works with both implementations
    def generate_reset_method(name)
      define_method("reset_#{name}!") do
        # Reset simple inline implementation
        computed_var = "@#{name}_computed"
        value_var = "@#{name}_value"
        exception_var = "@#{name}_exception"
        mutex_var = "@#{name}_mutex"
        
        if instance_variable_defined?(computed_var)
          # Thread-safe reset for simple implementation
          mutex = instance_variable_get(mutex_var)
          if mutex
            mutex.synchronize do
              instance_variable_set(computed_var, false)
              remove_instance_variable(value_var) if instance_variable_defined?(value_var)
              remove_instance_variable(exception_var) if instance_variable_defined?(exception_var)
            end
          else
            instance_variable_set(computed_var, false)
            remove_instance_variable(value_var) if instance_variable_defined?(value_var)
            remove_instance_variable(exception_var) if instance_variable_defined?(exception_var)
          end
          return
        end
        
        # Reset LazyValue implementation
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