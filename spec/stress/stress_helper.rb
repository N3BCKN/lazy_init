require_relative '../spec_helper'
require 'timeout'

RSpec.configure do |config|
  # Tag stress tests for selective running
  config.filter_run_excluding :stress unless ENV['RUN_STRESS_TESTS']

  config.around(:each, :stress) do |example|
    begin
      Timeout::timeout(300) do  # 5 minutes
        example.run
      end
    rescue Timeout::Error
      fail "Stress test timed out after 5 minutes"
    end
  end

  # Memory cleanup after stress tests
  config.after(:each, :stress) do
    3.times do
      GC.start
      GC.compact if GC.respond_to?(:compact)
    end
  end
end