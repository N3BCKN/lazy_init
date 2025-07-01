# frozen_string_literal: true

module LazyInit
  # Class methods for defining lazy attributes and class variables.
  #
  # This module is automatically extended when a class includes or extends LazyInit.
  # It provides the core functionality for thread-safe lazy initialization.
  #
  # @example Basic usage
  #   class MyService
  #     extend LazyInit
  #     
  #     lazy_attr_reader :database_connection do
  #       Database.connect(ENV['DATABASE_URL'])
  #     end
  #   end
  #
  # @see LazyInit
  # @since 0.1.0
  module ClassMethods
    # Initializes the class with necessary instance variables for thread safety.
    #
    # @param base [Class] the class being extended
    # @return [void]
    # @api private
    def self.extended(base)
      base.instance_variable_set(:@lazy_init_class_mutex, Mutex.new)
      base.instance_variable_set(:@dependency_resolver, DependencyResolver.new(base))
    end

    # Defines a lazy-initialized instance attribute.
    #
    # The attribute will be computed only once per instance when first accessed.
    # Subsequent calls return the cached value. The computation is thread-safe.
    #
    # @param name [Symbol, String] the attribute name
    # @param timeout [Numeric, nil] timeout in seconds for the computation
    # @param depends_on [Array<Symbol>, Symbol, nil] other attributes this depends on
    # @param if_condition [Proc, nil] condition that must be true to compute the value
    # @param block [Proc] the computation block
    # @return [void]
    # @raise [ArgumentError] if no block is provided or name is invalid
    # @raise [InvalidAttributeNameError] if the attribute name is invalid
    #
    # @example Simple lazy attribute
    #   lazy_attr_reader :expensive_data do
    #     fetch_from_external_api
    #   end
    #
    # @example With timeout
    #   lazy_attr_reader :api_client, timeout: 5 do
    #     ApiClient.new(slow_endpoint_url)
    #   end
    #
    # @example With dependencies
    #   lazy_attr_reader :config do
    #     load_configuration
    #   end
    #   
    #   lazy_attr_reader :database, depends_on: [:config] do
    #     Database.connect(config.database_url)
    #   end
    #
    # @example With conditional loading
    #   lazy_attr_reader :debug_tools, if_condition: -> { Rails.env.development? } do
    #     ExpensiveDebugTools.new
    #   end
    #
    # Generated methods:
    # - `#{name}` - returns the computed value
    # - `#{name}_computed?` - returns true if value has been computed
    # - `reset_#{name}!` - resets the attribute to uncomputed state
    def lazy_attr_reader(name, timeout: nil, depends_on: nil, if_condition: nil, &block)
      validate_attribute_name!(name)
      raise ArgumentError, 'Block is required' unless block

      config = { 
        block: block, 
        timeout: timeout || LazyInit.configuration.default_timeout,
        depends_on: depends_on,
        condition: if_condition
      }
      lazy_initializers[name] = config

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

    # Defines a lazy-initialized class variable shared across all instances.
    #
    # The variable will be computed only once per class when first accessed.
    # All instances of the class will share the same computed value.
    #
    # @param name [Symbol, String] the class variable name
    # @param timeout [Numeric, nil] timeout in seconds for the computation
    # @param depends_on [Array<Symbol>, Symbol, nil] other attributes this depends on
    # @param if_condition [Proc, nil] condition that must be true to compute the value
    # @param block [Proc] the computation block
    # @return [void]
    # @raise [ArgumentError] if no block is provided or name is invalid
    # @raise [InvalidAttributeNameError] if the attribute name is invalid
    #
    # @example Shared connection pool
    #   lazy_class_variable :connection_pool do
    #     ConnectionPool.new(size: 20)
    #   end
    #
    # @example With timeout and condition
    #   lazy_class_variable :redis_client, 
    #     timeout: 10,
    #     if_condition: -> { ENV['REDIS_ENABLED'] == 'true' } do
    #     Redis.new(url: ENV['REDIS_URL'])
    #   end
    #
    # Generated methods:
    # - Class methods: `ClassName.#{name}`, `ClassName.#{name}_computed?`, `ClassName.reset_#{name}!`
    # - Instance methods: `#{name}`, `#{name}_computed?`, `reset_#{name}!` (delegates to class methods)
    def lazy_class_variable(name, timeout: nil, depends_on: nil, if_condition: nil, &block)
      validate_attribute_name!(name)
      raise ArgumentError, 'Block is required' unless block

      class_variable_name = "@@#{name}_lazy_value"

      if depends_on
        dependency_resolver.add_dependency(name, depends_on)
      end

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

      define_method(name) { self.class.send(name) }
      define_method("#{name}_computed?") { self.class.send("#{name}_computed?") }
      define_method("reset_#{name}!") { self.class.send("reset_#{name}!") }
    end

    # Returns the hash of all lazy initializers defined on this class.
    #
    # @return [Hash<Symbol, Hash>] mapping of attribute names to their configuration
    # @api private
    def lazy_initializers
      @lazy_initializers ||= {}
    end

    # Returns the dependency resolver for this class.
    #
    # @return [DependencyResolver] the dependency resolver instance
    # @api private
    def dependency_resolver
      @dependency_resolver ||= DependencyResolver.new(self)
    end

    private

    # Determines if an attribute can use the optimized simple implementation.
    #
    # @param timeout [Object] timeout configuration
    # @param depends_on [Object] dependency configuration
    # @param if_condition [Object] condition configuration
    # @return [Boolean] true if simple implementation can be used
    def simple_case?(timeout, depends_on, if_condition)
      timeout.nil? && (depends_on.nil? || depends_on.empty?) && if_condition.nil?
    end

    # Generates an optimized inline method for simple attributes.
    #
    # @param name [Symbol] the attribute name
    # @param block [Proc] the computation block
    # @return [void]
    def generate_simple_inline_method(name, block)
      computed_var = "@#{name}_computed"
      value_var = "@#{name}_value"
      exception_var = "@#{name}_exception"
      
      cached_block = block

      define_method(name) do
        return instance_variable_get(value_var) if instance_variable_get(computed_var)

        mutex = self.class.instance_variable_get(:@lazy_init_simple_mutex)
        unless mutex
          mutex = Mutex.new
          self.class.instance_variable_set(:@lazy_init_simple_mutex, mutex)
        end

        mutex.synchronize do
          if instance_variable_get(computed_var)
            stored_exception = instance_variable_get(exception_var)
            raise stored_exception if stored_exception
            return instance_variable_get(value_var)
          end

          begin
            result = instance_eval(&cached_block)
            
            instance_variable_set(value_var, result)
            instance_variable_set(computed_var, true)
            result
          rescue StandardError => e
            instance_variable_set(exception_var, e)
            instance_variable_set(computed_var, true)
            raise
          end
        end
      end
    end

    # Generates a method using LazyValue for complex attributes.
    #
    # @param name [Symbol] the attribute name
    # @param config [Hash] the attribute configuration
    # @return [void]
    def generate_complex_lazyvalue_method(name, config)
      cached_timeout = config[:timeout]
      cached_depends_on = config[:depends_on]
      cached_condition = config[:condition]
      cached_block = config[:block]

      define_method(name) do
        if cached_condition
          condition_result = instance_exec(&cached_condition)
          return nil unless condition_result
        end

        if cached_depends_on
          self.class.dependency_resolver.resolve_dependencies(name, self)
        end

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

    # Generates the predicate method for checking computed state.
    #
    # @param name [Symbol] the attribute name
    # @return [void]
    def generate_predicate_method(name)
      define_method("#{name}_computed?") do
        computed_var = "@#{name}_computed"
        exception_var = "@#{name}_exception"
        
        if instance_variable_defined?(computed_var)
          return instance_variable_get(computed_var) && !instance_variable_get(exception_var)
        end
        
        lazy_var = "@#{name}_lazy_value"
        if instance_variable_defined?(lazy_var)
          lazy_value = instance_variable_get(lazy_var)
          return lazy_value&.computed? || false
        end
        
        false
      end
    end

    # Generates the reset method for clearing computed state.
    #
    # @param name [Symbol] the attribute name
    # @return [void]
    def generate_reset_method(name)
      define_method("reset_#{name}!") do
        computed_var = "@#{name}_computed"
        value_var = "@#{name}_value"
        exception_var = "@#{name}_exception"
        
        if instance_variable_defined?(computed_var)
          mutex = self.class.instance_variable_get(:@lazy_init_simple_mutex)
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
        
        lazy_var = "@#{name}_lazy_value"
        if instance_variable_defined?(lazy_var)
          lazy_value = instance_variable_get(lazy_var)
          lazy_value&.reset!
          remove_instance_variable(lazy_var)
        end
      end
    end

    # Validates that the attribute name is valid.
    #
    # @param name [Object] the attribute name to validate
    # @return [void]
    # @raise [InvalidAttributeNameError] if the name is invalid
    def validate_attribute_name!(name)
      raise InvalidAttributeNameError, 'Attribute name cannot be nil' if name.nil?
      raise InvalidAttributeNameError, 'Attribute name cannot be empty' if name.to_s.strip.empty?
      raise InvalidAttributeNameError, 'Attribute name must be a symbol or string' unless name.is_a?(Symbol) || name.is_a?(String)
      
      name_str = name.to_s
      raise InvalidAttributeNameError, "Invalid attribute name: #{name_str}" unless name_str.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*[?!]?\z/)
    end
  end
end