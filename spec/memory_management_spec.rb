# frozen_string_literal: true

RSpec.describe 'Memory Management' do
  let(:test_class) { Class.new { include LazyInit } }

  describe 'lazy_once with TTL' do
    it 'expires entries after TTL' do
      instance = test_class.new
      
      def instance.test_method
        lazy_once(ttl: 0.1) { Time.now.to_f }
      end
      
      first_value = instance.test_method
      sleep(0.15)  # Wait for TTL to expire
      
      # Access again to trigger cleanup
      def instance.trigger_cleanup
        lazy_once(ttl: 0.1) { 'trigger' }
      end
      instance.trigger_cleanup
      
      second_value = instance.test_method
      expect(second_value).not_to eq(first_value)
    end
  end

  describe 'lazy_once with max_entries' do
    it 'limits cache size using LRU eviction' do
      instance = test_class.new
      
      # Create more entries than max_entries
      10.times do |i|
        instance.define_singleton_method("method_#{i}") do
          lazy_once(max_entries: 5) { "value_#{i}" }
        end
        instance.send("method_#{i}")
      end
      
      stats = instance.lazy_once_statistics
      expect(stats[:total_entries]).to be <= 5
    end
  end

  describe 'lazy_once statistics' do
    it 'tracks access patterns' do
      instance = test_class.new
      
      def instance.frequently_used
        lazy_once { 'frequent_value' }
      end
      
      def instance.rarely_used
        lazy_once { 'rare_value' }
      end
      
      # Access one method more than the other
      5.times { instance.frequently_used }
      1.times { instance.rarely_used }
      
      stats = instance.lazy_once_statistics
      expect(stats[:total_entries]).to eq(2)
      expect(stats[:computed_entries]).to eq(2)
      expect(stats[:total_accesses]).to eq(6)
      expect(stats[:average_accesses]).to eq(3.0)
    end
  end

  describe 'memory cleanup' do
    it 'clears all lazy_once values' do
      instance = test_class.new
      
      def instance.test_method
        lazy_once { rand(1000) }
      end
      
      first_value = instance.test_method
      expect(instance.lazy_once_statistics[:total_entries]).to eq(1)
      
      instance.clear_lazy_once_values!
      expect(instance.lazy_once_statistics[:total_entries]).to eq(0)
      
      second_value = instance.test_method
      expect(second_value).not_to eq(first_value)
    end
  end
end