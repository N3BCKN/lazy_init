# frozen_string_literal: true

RSpec.describe 'Conditional Loading' do
  let(:test_class) do
    Class.new do
      extend LazyInit
      attr_accessor :feature_enabled
      
      def initialize
        @feature_enabled = true
      end
      
      lazy_attr_reader :conditional_feature, if_condition: -> { feature_enabled } do
        'feature_loaded'
      end
      
      lazy_attr_reader :always_feature do
        'always_loaded'
      end
    end
  end

  it 'loads when condition is true' do
    instance = test_class.new
    instance.feature_enabled = true
    
    expect(instance.conditional_feature).to eq('feature_loaded')
    expect(instance.conditional_feature_computed?).to be true
  end

  it 'returns nil when condition is false' do
    instance = test_class.new
    instance.feature_enabled = false
    
    expect(instance.conditional_feature).to be_nil
    expect(instance.conditional_feature_computed?).to be false
  end

  it 'loads unconditional features regardless of condition' do
    instance = test_class.new
    instance.feature_enabled = false
    
    expect(instance.always_feature).to eq('always_loaded')
    expect(instance.always_feature_computed?).to be true
  end

  it 'evaluates condition dynamically' do
    instance = test_class.new
    
    instance.feature_enabled = false
    expect(instance.conditional_feature).to be_nil
    
    instance.feature_enabled = true
    expect(instance.conditional_feature).to eq('feature_loaded')
  end
end