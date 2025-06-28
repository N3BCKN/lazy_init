require_relative '../spec_helper'

RSpec.configure do |config|
  # Tag stress tests for selective running
  config.filter_run_excluding :stress unless ENV['RUN_STRESS_TESTS']

  # Longer timeout for stress tests
  config.around(:each, :stress) do |example|
    original_timeout = RSpec.configuration.timeout
    RSpec.configuration.timeout = 300 # 5 minutes

    begin
      example.run
    ensure
      RSpec.configuration.timeout = original_timeout
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
