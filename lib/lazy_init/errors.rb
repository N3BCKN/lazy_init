# frozen_string_literal: true

module LazyInit
  # Base exception class for all LazyInit errors.
  #
  # @since 0.1.0
  class Error < StandardError; end

  # Raised when an invalid attribute name is provided to lazy_attr_reader.
  #
  # @since 0.1.0
  class InvalidAttributeNameError < Error; end

  # Raised when lazy initialization exceeds the configured timeout.
  #
  # @since 0.1.0
  class TimeoutError < Error; end

  # Raised when circular dependencies are detected in attribute resolution.
  #
  # @since 0.1.0
  class DependencyError < Error; end
end
