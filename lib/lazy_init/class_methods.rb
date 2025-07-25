# frozen_string_literal: true

module LazyInit
  # Class-level methods for defining lazy attributes with Ruby version-specific optimizations.
  #
  # Automatically selects the most efficient implementation:
  # - Ruby 3+: eval-based methods for maximum performance
  # - Ruby 2.6+: define_method with full compatibility
  # - Simple cases: inline variables, dependency cases: lightweight resolution
  # - Complex cases: full LazyValue with timeout and dependency support
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
  # @example With dependencies
  #   lazy_attr_reader :database, depends_on: [:config] do
  #     Database.connect(config.database_url)
  #   end
  #
  # @since 0.1.0
  module ClassMethods
    # Set up necessary infrastructure when LazyInit is extended by a class.
    #
    # @param base [Class] the class being extended with LazyInit
    # @return [void]
    # @api private
    def self.extended(base)
      base.instance_variable_set(:@lazy_init_class_mutex, Mutex.new)
    end

    # Registry of all lazy initializers defined on this class.
    #
    # @return [Hash<Symbol, Hash>] mapping of attribute names to their configuration
    def lazy_initializers
      @lazy_initializers ||= {}
    end

    # Lazy dependency resolver - created only when needed for performance.
    #
    # @return [DependencyResolver] the resolver instance for this class
    def dependency_resolver
      @dependency_resolver ||= DependencyResolver.new(self)
    end

    # Define a thread-safe lazy-initialized instance attribute.
    #
    # Automatically optimizes based on Ruby version and complexity:
    # - Ruby 3+: uses eval for maximum performance
    # - Simple cases: direct instance variables
    # - Dependencies: lightweight resolution for single deps, full resolver for complex
    # - Timeouts: full LazyValue wrapper
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

      # store configuration for introspection
      config = {
        block: block,
        timeout: timeout || LazyInit.configuration.default_timeout,
        depends_on: depends_on
      }
      lazy_initializers[name] = config

      # register dependencies with resolver if present
      dependency_resolver.add_dependency(name, depends_on) if depends_on

      # select optimal implementation strategy
      if depends_on && Array(depends_on).size == 1 && !timeout
        generate_simple_dependency_with_inline_check(name, Array(depends_on).first, block)
        generate_predicate_method(name)
        generate_reset_method(name)
      elsif depends_on && Array(depends_on).size > 1 && !timeout
        generate_fast_dependency_method(name, depends_on, block, config)
        generate_predicate_method(name)
        generate_reset_method_with_deps_flag(name)
      elsif simple_case_eligible?(timeout, depends_on)
        generate_optimized_simple_method(name, block)
      elsif enhanced_simple_case?(timeout, depends_on)
        if simple_dependency_case?(depends_on)
          generate_lazy_compiling_method(name, block, :dependency, depends_on)
        else
          generate_lazy_compiling_method(name, block, :simple, nil)
        end
        generate_predicate_method(name)
        generate_reset_method(name)
      else
        generate_complex_lazyvalue_method(name, config)
        generate_predicate_method(name)
        generate_reset_method(name)
      end
    end

    # Define a thread-safe lazy-initialized class variable shared across all instances.
    #
    # Uses full LazyValue wrapper for thread safety and feature completeness.
    # All instances share the same computed value.
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

      # register dependencies for class-level attributes
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

    # Generate optimized methods based on dependency type and Ruby version.
    #
    # @param name [Symbol] the attribute name
    # @param block [Proc] the computation block
    # @param dependency_type [Symbol] :simple or :dependency
    # @param depends_on [Array<Symbol>, Symbol, nil] dependencies for :dependency type
    # @return [void]
    # @api private
    def generate_lazy_compiling_method(name, block, dependency_type = :simple, depends_on = nil)
      case dependency_type
      when :dependency
        if depends_on && Array(depends_on).size == 1
          # single dependency: fast path with lightweight resolution
          generate_simple_dependency_with_resolution(name, depends_on, block)
        else
          # complex dependency: full LazyValue with complex resolution
          config = { block: block, timeout: nil, depends_on: depends_on }
          generate_complex_lazyvalue_method(name, config)
        end
      when :simple
        # no dependencies: fastest path
        if LazyInit::RubyCapabilities::IMPROVED_EVAL_PERFORMANCE
          generate_simple_inline_method_with_eval(name, block)
        else
          generate_simple_inline_method_with_define_method(name, block)
        end
      end
    end

    # Check if attribute qualifies for simple optimization (no timeout, simple dependencies).
    #
    # @param timeout [Object] timeout configuration
    # @param depends_on [Object] dependency configuration
    # @return [Boolean] true if simple implementation should be used
    def enhanced_simple_case?(timeout, depends_on)
      return false unless timeout.nil?

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
    # @param depends_on [Object] dependency configuration
    # @return [Boolean] true if simple dependency method should be used
    def simple_dependency_case?(depends_on)
      return false if depends_on.nil? || depends_on.empty?

      Array(depends_on).size == 1
    end

    # Generate full LazyValue method for complex scenarios (timeout, multiple dependencies).
    #
    # @param name [Symbol] the attribute name
    # @param config [Hash] the attribute configuration
    # @return [void]
    def generate_complex_lazyvalue_method(name, config)
      cached_timeout = config[:timeout]
      cached_depends_on = config[:depends_on]
      cached_block = config[:block]

      define_method(name) do
        # resolve dependencies using full dependency resolver
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

    # Generate predicate method to check computation state.
    # Handles both simple (inline variables) and complex (LazyValue) cases.
    #
    # @param name [Symbol] the attribute name
    # @return [void]
    def generate_predicate_method(name)
      define_method("#{name}_computed?") do
        # check simple implementation first
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

        false
      end
    end

    # Generate reset method to clear computed state and allow recomputation.
    # Handles both simple and complex implementations.
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
          # use mutex if available for thread safety
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

        # handle complex implementation reset (LazyValue)
        lazy_var = "@#{name}_lazy_value"
        if instance_variable_defined?(lazy_var)
          lazy_value = instance_variable_get(lazy_var)
          lazy_value&.reset!
          remove_instance_variable(lazy_var)
        end
      end
    end

    # Validate attribute name follows Ruby conventions.
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

    # Ruby 3+ eval-based method generation for simple methods (no dependencies).
    # Optimized for maximum performance with minimal overhead.
    #
    # @param name [Symbol] attribute name
    # @param block [Proc] computation block
    # @return [void]
    def generate_simple_inline_method_with_eval(name, block)
      block_var = "@@lazy_#{name}_block_#{object_id}"
      class_variable_set(block_var, block)

      method_code = <<~RUBY
        def #{name}
          # fast path: return cached value immediately if available
          return @#{name}_value if @#{name}_computed

          # shared mutex for thread safety - avoid per-method mutex overhead
          mutex = self.class.instance_variable_get(:@lazy_init_simple_mutex)
          unless mutex
            mutex = Mutex.new
            self.class.instance_variable_set(:@lazy_init_simple_mutex, mutex)
          end

          mutex.synchronize do
            # double-check pattern: another thread might have computed while we waited
            if @#{name}_computed
              stored_exception = @#{name}_exception
              raise stored_exception if stored_exception
              return @#{name}_value
            end

            begin
              # perform computation and cache result
              block = self.class.class_variable_get(:#{block_var})
              result = instance_eval(&block)
              @#{name}_value = result
              @#{name}_computed = true
              result
            rescue StandardError => e
              # cache exceptions to ensure consistent error behavior
              @#{name}_exception = e
              @#{name}_computed = true
              raise
            end
          end
        end
      RUBY

      class_eval(method_code)
    end

    # Ruby 2.6+ fallback using define_method for simple methods.
    # Compatible version of the eval-based simple method.
    #
    # @param name [Symbol] attribute name
    # @param block [Proc] computation block
    # @return [void]
    def generate_simple_inline_method_with_define_method(name, block)
      computed_var = "@#{name}_computed"
      value_var = "@#{name}_value"
      exception_var = "@#{name}_exception"

      cached_block = block

      define_method(name) do
        # fast path: return cached value immediately if available
        return instance_variable_get(value_var) if instance_variable_get(computed_var)

        # shared mutex for thread safety
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

    # Generate single dependency method with lightweight resolution.
    # Uses eval or define_method based on Ruby version capabilities.
    #
    # @param name [Symbol] attribute name
    # @param depends_on [Array<Symbol>, Symbol] dependency specification
    # @param block [Proc] computation block
    # @return [void]
    def generate_simple_dependency_with_resolution(name, depends_on, block)
      dep_name = Array(depends_on).first
      dependency_resolver.add_dependency(name, depends_on)

      if LazyInit::RubyCapabilities::IMPROVED_EVAL_PERFORMANCE
        generate_fast_dependency_method_with_eval(name, dep_name, block)
      else
        generate_fast_dependency_method_with_define_method(name, dep_name, block)
        generate_predicate_method(name)
        generate_reset_method(name)
      end
    end

    # Ruby 3+ eval-based fast dependency method with circular detection.
    # Includes predicate and reset methods in single eval call for performance.
    #
    # @param name [Symbol] attribute name
    # @param dep_name [Symbol] dependency attribute name
    # @param block [Proc] computation block
    # @return [void]
    def generate_fast_dependency_method_with_eval(name, dep_name, block)
      block_var = "@@lazy_#{name}_block_#{object_id}"
      class_variable_set(block_var, block)

      method_code = <<~RUBY
        def #{name}
          if @#{name}_computed
            stored_exception = @#{name}_exception
            raise stored_exception if stored_exception
            return @#{name}_value
          end

          # circular dependency detection
          resolution_stack = Thread.current[:lazy_init_resolution_stack] ||= []
          if resolution_stack.include?(:#{name})
            circular_error = LazyInit::DependencyError.new(
              "Circular dependency detected: \#{resolution_stack.join(' -> ')} -> #{name}"
            )
            @#{name}_exception = circular_error
            @#{name}_computed = true
            raise circular_error
          end

          # lightweight dependency resolution with circular protection
          resolution_stack.push(:#{name})
          begin
            #{dep_name} unless #{dep_name}_computed?
          ensure
            resolution_stack.pop
            Thread.current[:lazy_init_resolution_stack] = nil if resolution_stack.empty?
          end

          @#{name}_mutex ||= Mutex.new
          @#{name}_mutex.synchronize do
            if @#{name}_computed
              stored_exception = @#{name}_exception#{'  '}
              raise stored_exception if stored_exception
              return @#{name}_value
            end

            begin
              block = self.class.class_variable_get(:#{block_var})
              result = instance_eval(&block)
              @#{name}_value = result
              @#{name}_computed = true
              result
            rescue StandardError => e
              @#{name}_exception = e
              @#{name}_computed = true
              raise
            end
          end
        end

        # generate compatible predicate method
        def #{name}_computed?
          @#{name}_computed && !@#{name}_exception
        end

        # generate compatible reset method
        def reset_#{name}!
          @#{name}_mutex&.synchronize do
            @#{name}_computed = false
            @#{name}_value = nil
            @#{name}_exception = nil
          end
        end
      RUBY

      class_eval(method_code)
    end

    # Ruby 2.6+ define_method version of fast dependency method.
    # Provides same functionality as eval version with full compatibility.
    #
    # @param name [Symbol] attribute name
    # @param dep_name [Symbol] dependency attribute name
    # @param block [Proc] computation block
    # @return [void]
    def generate_fast_dependency_method_with_define_method(name, dep_name, block)
      computed_var = "@#{name}_computed"
      value_var = "@#{name}_value"
      exception_var = "@#{name}_exception"

      cached_block = block
      cached_dep_name = dep_name

      define_method(name) do
        # fast path with exception check
        if instance_variable_get(computed_var)
          stored_exception = instance_variable_get(exception_var)
          raise stored_exception if stored_exception

          return instance_variable_get(value_var)
        end

        # circular dependency detection
        resolution_stack = Thread.current[:lazy_init_resolution_stack] ||= []
        if resolution_stack.include?(name)
          circular_error = LazyInit::DependencyError.new(
            "Circular dependency detected: #{resolution_stack.join(' -> ')} -> #{name}"
          )
          # cache the error
          instance_variable_set(exception_var, circular_error)
          instance_variable_set(computed_var, true)
          raise circular_error
        end

        # lightweight dependency resolution with circular protection
        resolution_stack.push(name)
        begin
          send(cached_dep_name) unless send("#{cached_dep_name}_computed?")
        ensure
          resolution_stack.pop
          Thread.current[:lazy_init_resolution_stack] = nil if resolution_stack.empty?
        end

        # thread-safe computation
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

    def simple_case_eligible?(timeout, depends_on)
      timeout.nil? && 
      (depends_on.nil? || depends_on.empty?) && LazyInit::RubyCapabilities::RUBY_3_PLUS
    end

    def generate_optimized_simple_method(name, block)
      if LazyInit::RubyCapabilities::RUBY_3_PLUS
        generate_ruby3_ultra_simple_method(name, block)
      else
        # Fallback to existing implementation
        generate_simple_inline_method_with_define_method(name, block)
      end
      
      generate_simple_helpers(name)
    end

    # Generate ultra-optimized method for Ruby 3+ simple cases.
    #
    # Uses eval-based method generation with shared mutex and direct
    # instance variable access for maximum performance. Stores computation
    # block in class variable for fast access.
    #
    # @param name [Symbol] attribute name
    # @param block [Proc] computation block
    # @return [void]
    # @api private
    def generate_ruby3_ultra_simple_method(name, block)
      ensure_shared_mutex
      
      block_var = "@@simple_#{name}_#{object_id}"
      class_variable_set(block_var, block)

      method_code = <<~RUBY
        def #{name}
          return @#{name}_value if defined?(@#{name}_value)

          shared_mutex = self.class.instance_variable_get(:@shared_mutex)
          shared_mutex.synchronize do
            return @#{name}_value if defined?(@#{name}_value)
            raise @#{name}_exception if defined?(@#{name}_exception)

            begin
              @#{name}_value = instance_eval(&self.class.class_variable_get(:#{block_var}))
            rescue StandardError => e
              @#{name}_exception = e
              raise
            end
          end
        end
      RUBY

      class_eval(method_code)
    end

    # Generate predicate and reset helper methods for simple cases.
    #
    # Creates computed? and reset! methods that work with the direct
    # instance variable approach used by simple case optimization.
    #
    # @param name [Symbol] attribute name
    # @return [void]
    # @api private
    def generate_simple_helpers(name)
      define_method("#{name}_computed?") do
        instance_variable_defined?("@#{name}_value") && !instance_variable_defined?("@#{name}_exception")
      end

      define_method("reset_#{name}!") do
        shared_mutex = self.class.instance_variable_get(:@shared_mutex)
        shared_mutex.synchronize do
          remove_instance_variable("@#{name}_value") if instance_variable_defined?("@#{name}_value")
          remove_instance_variable("@#{name}_exception") if instance_variable_defined?("@#{name}_exception")
        end
      end
    end

    # Ensure shared mutex exists for simple case optimization.
    #
    # Creates a class-level mutex shared by all simple attributes to
    # reduce memory overhead compared to per-attribute mutexes.
    #
    # @return [void]
    # @api private
    def ensure_shared_mutex
      return if instance_variable_defined?(:@shared_mutex)
      @shared_mutex = Mutex.new
    end

    # Generate optimized method for single dependency attributes.
    #
    # Bypasses dependency resolver overhead by directly checking and
    # resolving single dependencies inline. Includes circular dependency
    # detection and thread-safe computation.
    #
    # @param name [Symbol] attribute name
    # @param dep_name [Symbol] dependency attribute name
    # @param block [Proc] computation block
    # @return [void]
    # @api private
    def generate_simple_dependency_with_inline_check(name, dep_name, block)
      cached_block = block
      cached_dep_name = dep_name
      computed_var = "@#{name}_computed"
      value_var = "@#{name}_value"
      exception_var = "@#{name}_exception"

      define_method(name) do
        # Fast path: return cached result
        return instance_variable_get(value_var) if instance_variable_get(computed_var)

        # Circular dependency detection BEFORE mutex
        resolution_stack = Thread.current[:lazy_init_resolution_stack] ||= []
        if resolution_stack.include?(name)
          circular_error = LazyInit::DependencyError.new(
            "Circular dependency detected: #{resolution_stack.join(' -> ')} -> #{name}"
          )
          raise circular_error
        end

        resolution_stack.push(name)
        begin
          # Inline dependency check
          unless send("#{cached_dep_name}_computed?")
            send(cached_dep_name)
          end

          # Thread-safe computation
          mutex = self.class.instance_variable_get(:@lazy_init_class_mutex)
          mutex.synchronize do
            return instance_variable_get(value_var) if instance_variable_get(computed_var)
            
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
        ensure
          resolution_stack.pop
          Thread.current[:lazy_init_resolution_stack] = nil if resolution_stack.empty?
        end
      end
    end

    # Generate reset method that clears dependency resolution flag.
    #
    # Used by attributes with dependency caching to ensure dependencies
    # are re-resolved after reset. Thread-safe operation that clears
    # both computed state and dependency resolution state.
    #
    # @param name [Symbol] attribute name
    # @return [void]
    # @api private
    def generate_reset_method_with_deps_flag(name)
      computed_var = "@#{name}_computed"
      value_var = "@#{name}_value"
      exception_var = "@#{name}_exception"
      deps_resolved_var = "@#{name}_deps_resolved"

      define_method("reset_#{name}!") do
        mutex = self.class.instance_variable_get(:@lazy_init_class_mutex)
        mutex.synchronize do
          remove_instance_variable(value_var) if instance_variable_defined?(value_var)
          remove_instance_variable(exception_var) if instance_variable_defined?(exception_var)
          instance_variable_set(computed_var, false)
          instance_variable_set(deps_resolved_var, false)  # Reset dependency flag
        end
      end
    end

    # Generate method with cached dependency resolution for multiple dependencies.
    #
    # Optimizes attributes with multiple dependencies by caching the dependency
    # resolution step. Once dependencies are resolved for an instance, subsequent
    # calls skip the dependency resolver entirely.
    #
    # @param name [Symbol] attribute name
    # @param depends_on [Array<Symbol>] dependency attributes
    # @param block [Proc] computation block
    # @param config [Hash] attribute configuration
    # @return [void]
    # @api private
    def generate_fast_dependency_method(name, depends_on, block, config)
      cached_block = block
      cached_depends_on = depends_on
      computed_var = "@#{name}_computed"
      value_var = "@#{name}_value"
      exception_var = "@#{name}_exception"
      deps_resolved_var = "@#{name}_deps_resolved"  # flag for resolved deps

      define_method(name) do
        # Fast path: return cached result
        return instance_variable_get(value_var) if instance_variable_get(computed_var)

        # Fast dependency check: skip resolution if already resolved
        unless instance_variable_get(deps_resolved_var)
          # Only resolve dependencies once
          self.class.dependency_resolver.resolve_dependencies(name, self)
          instance_variable_set(deps_resolved_var, true)
        end

        # Thread-safe computation
        mutex = self.class.instance_variable_get(:@lazy_init_class_mutex)
        mutex.synchronize do
          return instance_variable_get(value_var) if instance_variable_get(computed_var)
          
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
  end
end