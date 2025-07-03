# frozen_string_literal: true

require_relative 'lazy_init/version'
require_relative 'lazy_init/lazy_value'
require_relative 'lazy_init/class_methods'
require_relative 'lazy_init/instance_methods'
require_relative 'lazy_init/errors'
require_relative 'lazy_init/configuration'
require_relative 'lazy_init/dependency_resolver'
require_relative 'lazy_init/complex_dependencies_debugger'
require_relative 'lazy_init/method_call_debugger'

# Thread-safe lazy initialization patterns for Ruby
#
# @example Basic usage
#   class ApiClient
#     extend LazyInit
#
#     lazy_attr_reader :connection do
#       HTTPClient.new(api_url)
#     end
#   end
#
# @example Class-level shared resources
#   class DatabaseManager
#     extend LazyInit
#
#     lazy_class_variable :connection_pool do
#       ConnectionPool.new(size: 20)
#     end
#   end
module LazyInit
  # Called when LazyInit is included in a class
  # Adds both class and instance methods
  #
  # @param base [Class] the class including this module
  def self.included(base)
    base.extend(ClassMethods)
    base.include(InstanceMethods)
  end

  # Called when LazyInit is extended by a class
  # Adds only class methods
  #
  # @param base [Class] the class extending this module
  def self.extended(base)
    base.extend(ClassMethods)
  end
end
