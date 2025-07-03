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
    # @!attribute [rw] default_timeout
    #   @return [Numeric, nil] default timeout in seconds for all lazy attributes (default: nil)

    # @!attribute [rw] max_lazy_once_entries
    #   @return [Integer] maximum entries in lazy_once cache (default: 1000)

    # @!attribute [rw] lazy_once_ttl
    #   @return [Numeric, nil] time-to-live for lazy_once entries in seconds (default: nil)

    attr_accessor :default_timeout, :max_lazy_once_entries, :lazy_once_ttl

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
