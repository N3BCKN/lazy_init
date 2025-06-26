# frozen_string_literal: true

RSpec.describe LazyInit::LazyValue do
  describe '#initialize' do
    it 'requires a block' do
      expect { described_class.new }.to raise_error(ArgumentError, 'Block is required')
    end

    it 'accepts a block' do
      lazy_value = described_class.new { 'test' }
      expect(lazy_value).to be_a(described_class)
    end
  end

  describe '#value' do
    it 'executes the block and returns the result' do
      lazy_value = described_class.new { 42 }
      expect(lazy_value.value).to eq(42)
    end

    it 'executes the block only once' do
      call_count = 0
      lazy_value = described_class.new do
        call_count += 1
        "result_#{call_count}"
      end

      first_result = lazy_value.value
      second_result = lazy_value.value

      expect(call_count).to eq(1)
      expect(first_result).to eq('result_1')
      expect(second_result).to eq('result_1')
    end

    it 'works with different return types' do
      string_lazy = described_class.new { 'hello' }
      number_lazy = described_class.new { 123 }
      array_lazy = described_class.new { [1, 2, 3] }
      hash_lazy = described_class.new { { key: 'value' } }
      nil_lazy = described_class.new { nil }

      expect(string_lazy.value).to eq('hello')
      expect(number_lazy.value).to eq(123)
      expect(array_lazy.value).to eq([1, 2, 3])
      expect(hash_lazy.value).to eq({ key: 'value' })
      expect(nil_lazy.value).to be_nil
    end

    context 'when block raises an exception' do
      let(:lazy_value) do
        described_class.new { raise StandardError, 'test error' }
      end

      it 'propagates the exception' do
        expect { lazy_value.value }.to raise_error(StandardError, 'test error')
      end

      it 'raises the same exception on subsequent calls' do
        expect { lazy_value.value }.to raise_error(StandardError, 'test error')
        expect { lazy_value.value }.to raise_error(StandardError, 'test error')
      end

      it 'does not execute the block again after exception' do
        call_count = 0
        failing_lazy = described_class.new do
          call_count += 1
          raise StandardError, "call_#{call_count}"
        end

        expect { failing_lazy.value }.to raise_error(StandardError, 'call_1')
        expect { failing_lazy.value }.to raise_error(StandardError, 'call_1')
        expect(call_count).to eq(1)
      end
    end
  end

  describe '#computed?' do
    it 'returns false initially' do
      lazy_value = described_class.new { 'test' }
      expect(lazy_value.computed?).to be false
    end

    it 'returns true after value is computed' do
      lazy_value = described_class.new { 'test' }
      lazy_value.value
      expect(lazy_value.computed?).to be true
    end

    it 'remains false if computation failed' do
      lazy_value = described_class.new { raise 'error' }
      expect { lazy_value.value }.to raise_error
      expect(lazy_value.computed?).to be false
    end
  end

  describe '#reset!' do
    it 'resets the computed state' do
      lazy_value = described_class.new { rand(1000) }
      
      first_value = lazy_value.value
      expect(lazy_value.computed?).to be true

      lazy_value.reset!
      expect(lazy_value.computed?).to be false

      second_value = lazy_value.value
      expect(lazy_value.computed?).to be true
      
      # Should potentially get different values (though there's a tiny chance they're the same)
      # More importantly, the block was executed again
    end

    it 'allows recomputation after reset' do
      call_count = 0
      lazy_value = described_class.new do
        call_count += 1
        "result_#{call_count}"
      end

      expect(lazy_value.value).to eq('result_1')
      lazy_value.reset!
      expect(lazy_value.value).to eq('result_2')
      expect(call_count).to eq(2)
    end

    it 'clears exception state' do
      call_count = 0
      lazy_value = described_class.new do
        call_count += 1
        raise 'error' if call_count == 1
        'success'
      end

      expect { lazy_value.value }.to raise_error('error')
      expect(lazy_value.exception?).to be true

      lazy_value.reset!
      expect(lazy_value.exception?).to be false
      expect(lazy_value.value).to eq('success')
    end
  end

  describe '#exception?' do
    it 'returns false initially' do
      lazy_value = described_class.new { 'test' }
      expect(lazy_value.exception?).to be false
    end

    it 'returns false after successful computation' do
      lazy_value = described_class.new { 'test' }
      lazy_value.value
      expect(lazy_value.exception?).to be false
    end

    it 'returns true after failed computation' do
      lazy_value = described_class.new { raise 'error' }
      expect { lazy_value.value }.to raise_error
      expect(lazy_value.exception?).to be true
    end
  end

  describe '#exception' do
    it 'returns nil initially' do
      lazy_value = described_class.new { 'test' }
      expect(lazy_value.exception).to be_nil
    end

    it 'returns nil after successful computation' do
      lazy_value = described_class.new { 'test' }
      lazy_value.value
      expect(lazy_value.exception).to be_nil
    end

    it 'returns the exception after failed computation' do
      error = StandardError.new('test error')
      lazy_value = described_class.new { raise error }
      
      expect { lazy_value.value }.to raise_error(error)
      expect(lazy_value.exception).to be(error)
    end
  end

  describe 'thread safety' do
    it 'ensures block is called only once with concurrent access' do
      call_count = 0
      lazy_value = described_class.new do
        # Add small delay to increase chance of race condition
        sleep(0.001)
        call_count += 1
        "result_#{call_count}"
      end

      results = run_in_threads(50) { lazy_value.value }

      expect(call_count).to eq(1)
      expect(results.uniq).to eq(['result_1'])
    end

    it 'handles rapid concurrent access correctly' do
      lazy_value = described_class.new { Time.now.to_f }
      
      results = run_in_threads(100) { lazy_value.value }
      
      # All threads should get the exact same timestamp
      expect(results.uniq.size).to eq(1)
    end

    it 'properly synchronizes computed? predicate' do
      lazy_value = described_class.new do
        sleep(0.01) # Ensure computation takes some time
        'result'
      end

      computed_checks = []
      value_results = []

      threads = 20.times.map do
        Thread.new do
          computed_checks << lazy_value.computed?
          value_results << lazy_value.value
          computed_checks << lazy_value.computed?
        end
      end

      threads.each(&:join)

      # After all threads complete, all should report as computed
      expect(value_results.uniq).to eq(['result'])
      expect(computed_checks.last(20)).to all(be true)
    end
  end
end