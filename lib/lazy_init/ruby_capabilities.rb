# frozen_string_literal: true

module LazyInit
  # Detects Ruby version capabilities for performance optimizations.
  #
  # This module automatically detects which Ruby version features are available
  # and enables appropriate optimizations without requiring configuration.
  # All detection is done at load time for zero runtime overhead.
  #
  # @since 0.2.0
  module RubyCapabilities
    # Currently used features
    # Ruby 3.0+ introduces significant performance improvements
    RUBY_3_PLUS = (RUBY_VERSION.split('.').map(&:to_i) <=> [3, 0, 0]) >= 0

    # Improved eval performance in Ruby 3.0+
    # Ruby 3+ has significantly better eval performance than define_method for generated code
    IMPROVED_EVAL_PERFORMANCE = RUBY_3_PLUS

    # Future optimization opportunities:
    # RUBY_3_2_PLUS = (RUBY_VERSION.split('.').map(&:to_i) <=> [3, 2, 0]) >= 0
    # OBJECT_SHAPES_AVAILABLE = RUBY_3_2_PLUS  # Faster ivar access
    # MN_SCHEDULER_AVAILABLE = RUBY_3_2_PLUS   # Better thread coordination
    # YJIT_AVAILABLE = RUBY_3_PLUS && !!defined?(RubyVM::YJIT)
    # IMPROVED_MUTEX_PERFORMANCE = RUBY_3_PLUS
    # FIBER_SCHEDULER_AVAILABLE = RUBY_3_PLUS && !!defined?(Fiber.set_scheduler)

    # Debug information for troubleshooting (only in development)
    unless defined?(Rails) && Rails.env.production?
      def self.report_capabilities
        {
          ruby_version: RUBY_VERSION,
          ruby_3_plus: RUBY_3_PLUS,
          improved_eval: IMPROVED_EVAL_PERFORMANCE
        }
      end
    end
  end
end
