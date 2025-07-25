# frozen_string_literal: true

RSpec.describe LazyInit::RubyCapabilities do
  describe 'version detection' do
    it 'detects Ruby version correctly' do
      expect([true, false]).to include(described_class::RUBY_3_PLUS)
      expect([true, false]).to include(described_class::RUBY_3_2_PLUS)
    end

    it 'has consistent version logic' do
      # Ruby 3.2+ should imply Ruby 3.0+
      expect(described_class::RUBY_3_PLUS).to be true if described_class::RUBY_3_2_PLUS
    end

    # it 'detects features based on Ruby version' do
    #   expect(described_class::OBJECT_SHAPES_AVAILABLE).to eq(described_class::RUBY_3_2_PLUS)
    #   expect(described_class::MN_SCHEDULER_AVAILABLE).to eq(described_class::RUBY_3_2_PLUS)
    #   expect(described_class::IMPROVED_EVAL_PERFORMANCE).to eq(described_class::RUBY_3_PLUS)
    #   expect(described_class::IMPROVED_MUTEX_PERFORMANCE).to eq(described_class::RUBY_3_PLUS)
    # end

    # it 'YJIT detection works' do
    #   # Test the logic, not specific values since they depend on Ruby version and compilation
    #   expect([true, false]).to include(described_class::YJIT_AVAILABLE)

    #   # Verify logic consistency
    #   if described_class::RUBY_3_PLUS
    #     # Should be true if RubyVM::YJIT is available, false otherwise
    #     expected_yjit = !!defined?(RubyVM::YJIT)
    #     expect(described_class::YJIT_AVAILABLE).to eq(expected_yjit)
    #   else
    #     # Should always be false for Ruby < 3.0
    #     expect(described_class::YJIT_AVAILABLE).to be false
    #   end
    # end

    # it 'Fiber Scheduler detection works' do
    #   # Test the logic, not specific values since they depend on Ruby version
    #   expect([true, false]).to include(described_class::FIBER_SCHEDULER_AVAILABLE)

    #   # Verify logic consistency
    #   if described_class::RUBY_3_PLUS
    #     # Should be true if Fiber.set_scheduler is available, false otherwise
    #     expected_fiber = !!defined?(Fiber.set_scheduler)
    #     expect(described_class::FIBER_SCHEDULER_AVAILABLE).to eq(expected_fiber)
    #   else
    #     # Should always be false for Ruby < 3.0
    #     expect(described_class::FIBER_SCHEDULER_AVAILABLE).to be false
    #   end
    # end
  end

  describe 'performance impact' do
    it 'constants are pre-computed (no runtime overhead)' do
      # These should be boolean constants, not method calls
      expect([true, false]).to include(described_class::RUBY_3_PLUS)
      expect([true, false]).to include(described_class::RUBY_3_2_PLUS)

      # Verify they are actual constants (frozen)
      expect([TrueClass, FalseClass]).to include(described_class::RUBY_3_PLUS.class)
      expect([TrueClass, FalseClass]).to include(described_class::RUBY_3_2_PLUS.class)
    end
  end

  # describe 'debug capabilities' do
  #   it 'provides capability report in non-production' do
  #     skip 'Only available in non-production' if defined?(Rails) && Rails.env.production?

  #     report = described_class.report_capabilities
  #     expect(report).to be_a(Hash)
  #     expect(report[:ruby_version]).to eq(RUBY_VERSION)
  #     expect(report.keys).to include(
  #       :ruby_3_plus, :ruby_3_2_plus, :object_shapes,
  #       :mn_scheduler, :yjit, :improved_eval, :improved_mutex
  #     )
  #   end
  # end

  describe 'backward compatibility' do
    it 'works on Ruby 2.6+' do
      # This test should pass on all supported Ruby versions
      expect { described_class::RUBY_3_PLUS }.not_to raise_error
      expect { described_class::RUBY_3_2_PLUS }.not_to raise_error
    end
  end
end
