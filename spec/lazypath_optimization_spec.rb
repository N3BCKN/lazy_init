# frozen_string_literal: true

RSpec.describe 'LazyValue Fast Path Optimization Verification' do
  describe 'fast path performance characteristics' do
    it 'eliminates exception checking from hot path' do
      lazy_value = LazyInit::LazyValue.new { 'computed_value' }
      
      # warm up - compute the value
      result = lazy_value.value
      expect(result).to eq('computed_value')
      expect(lazy_value.computed?).to be true
      
      # fast path should now be active
      # verify multiple calls return same result efficiently
      10.times do
        expect(lazy_value.value).to eq('computed_value')
      end
    end
    
    it 'maintains thread safety in fast path' do
      lazy_value = LazyInit::LazyValue.new { 'computed_value' }
      
      # warm up
      lazy_value.value
      
      # concurrent access to warm lazy value should be thread-safe
      results = []
      threads = 50.times.map do
        Thread.new do
          results << lazy_value.value
        end
      end
      
      threads.each(&:join)
      
      # all results should be identical
      expect(results.uniq).to eq(['computed_value'])
      expect(results.size).to eq(50)
    end
    
    it 'handles exceptions correctly without affecting fast path performance' do
      call_count = 0
      lazy_value = LazyInit::LazyValue.new do
        call_count += 1
        raise StandardError, 'computation failed'
      end
      
      # first call should raise exception
      expect { lazy_value.value }.to raise_error(StandardError, 'computation failed')
      expect(call_count).to eq(1)
      expect(lazy_value.computed?).to be false
      expect(lazy_value.exception?).to be true
      
      # subsequent calls should re-raise same exception (cached)
      expect { lazy_value.value }.to raise_error(StandardError, 'computation failed')
      expect { lazy_value.value }.to raise_error(StandardError, 'computation failed')
      expect(call_count).to eq(1) # block not called again
    end
    
    it 'allows recovery after reset from exception state' do
      attempt_count = 0
      lazy_value = LazyInit::LazyValue.new do
        attempt_count += 1
        raise 'fail' if attempt_count == 1
        'success on retry'
      end
      
      # first attempt fails
      expect { lazy_value.value }.to raise_error('fail')
      expect(lazy_value.exception?).to be true
      
      # reset and retry
      lazy_value.reset!
      expect(lazy_value.exception?).to be false
      expect(lazy_value.computed?).to be false
      
      # second attempt succeeds
      result = lazy_value.value
      expect(result).to eq('success on retry')
      expect(lazy_value.computed?).to be true
      expect(attempt_count).to eq(2)
    end
    
    it 'maintains atomic state transitions' do
      computation_started = false
      computation_finished = false
      
      lazy_value = LazyInit::LazyValue.new do
        computation_started = true
        sleep(0.01) # small delay to test atomicity
        computation_finished = true
        'computed_result'
      end
      
      # start computation in background
      thread = Thread.new { lazy_value.value }
      
      # wait a bit for computation to start
      sleep(0.005)
      
      # computed? should still be false until computation completes
      expect(lazy_value.computed?).to be false
      
      # wait for completion
      result = thread.value
      
      expect(result).to eq('computed_result')
      expect(lazy_value.computed?).to be true
      expect(computation_started).to be true
      expect(computation_finished).to be true
    end
  end
  
  describe 'performance regression prevention' do
    it 'fast path should be significantly faster than synchronized path' do
      require 'benchmark'
      
      # create lazy value and warm it up
      lazy_value = LazyInit::LazyValue.new { 'test_value' }
      lazy_value.value # warm up
      
      # measure fast path performance
      fast_path_time = Benchmark.realtime do
        100_000.times { lazy_value.value }
      end
      
      # create fresh lazy value that will always hit slow path
      always_slow = LazyInit::LazyValue.new { 'test_value' }
      
      # measure slow path performance (reset before each call)
      slow_path_time = Benchmark.realtime do
        100.times do
          always_slow.reset!
          always_slow.value
        end
      end
      
      # normalize to per-call basis
      fast_path_per_call = fast_path_time / 100_000
      slow_path_per_call = slow_path_time / 100
      
      # fast path should be at least 3x faster than slow path
      expect(slow_path_per_call).to be > (fast_path_per_call * 3)
      
      puts "Fast path: #{(fast_path_per_call * 1_000_000).round(2)} μs per call"
      puts "Slow path: #{(slow_path_per_call * 1_000_000).round(2)} μs per call"
      puts "Improvement: #{(slow_path_per_call / fast_path_per_call).round(2)}x faster"
    end
  end
  
  describe 'edge cases and error conditions' do
    it 'handles timeout correctly' do
      lazy_value = LazyInit::LazyValue.new(timeout: 0.1) do
        sleep(0.2) # longer than timeout
        'should not complete'
      end
      
      expect { lazy_value.value }.to raise_error(LazyInit::TimeoutError, /timed out after 0.1s/)
      expect(lazy_value.computed?).to be false
      expect(lazy_value.exception?).to be true
    end
    
    it 'handles nil return values correctly' do
      lazy_value = LazyInit::LazyValue.new { nil }
      
      result = lazy_value.value
      expect(result).to be_nil
      expect(lazy_value.computed?).to be true
      
      # subsequent calls should return cached nil
      expect(lazy_value.value).to be_nil
    end
    
    it 'handles false return values correctly' do
      lazy_value = LazyInit::LazyValue.new { false }
      
      result = lazy_value.value
      expect(result).to be false
      expect(lazy_value.computed?).to be true
      
      # subsequent calls should return cached false
      expect(lazy_value.value).to be false
    end
  end
end