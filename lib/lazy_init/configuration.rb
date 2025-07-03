# frozen_string_literal: true

module LazyInit
  # Global configuration for LazyInit gem behavior.
  #
  # Provides centralized configuration for timeout defaults and memory management settings.
  #
  # @example Basic configuration
  #   LazyInit.configure do |config|
  #     config.default_timeout = 30
  #     config.max_lazy_once_entries = 5000
  #   end
  #
  # @since 0.1.0
  class Configuration
    # Default timeout in seconds for all lazy attributes
    # @return [Numeric, nil] timeout value (default: nil)
    attr_accessor :default_timeout

    # Maximum entries in lazy_once cache
    # @return [Integer] maximum cache entries (default: 1000)
    attr_accessor :max_lazy_once_entries

    # Time-to-live for lazy_once entries in seconds
    # @return [Numeric, nil] TTL value (default: nil)
    attr_accessor :lazy_once_ttl

    # Initializes configuration with default values.
    def initialize
      @default_timeout = nil
      @max_lazy_once_entries = 1000
      @lazy_once_ttl = nil
    end
  end

  # Returns the global configuration instance.
  #
  # @return [Configuration] the current configuration object
  def self.configuration
    @configuration ||= Configuration.new
  end

  # Configures LazyInit global settings.
  #
  # @yield [Configuration] the configuration object to modify
  # @return [Configuration] the updated configuration
  #
  # @example Environment-specific configuration
  #   LazyInit.configure do |config|
  #     config.default_timeout = 10
  #     config.max_lazy_once_entries = 5000
  #     config.lazy_once_ttl = 1.hour
  #   end
  def self.configure
    yield(configuration)
  end
end
