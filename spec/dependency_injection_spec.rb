# frozen_string_literal: true

RSpec.describe 'Dependency Injection' do
  let(:test_class) do
    Class.new do
      extend LazyInit
      
      lazy_attr_reader :config do
        { database_url: 'postgresql://localhost/test' }
      end
      
      lazy_attr_reader :database, depends_on: [:config] do
        "Connected to: #{config[:database_url]}"
      end
      
      lazy_attr_reader :cache, depends_on: [:config, :database] do
        "Cache using #{database}"
      end
    end
  end

  it 'resolves dependencies in correct order' do
    instance = test_class.new
    
    expect(instance.config_computed?).to be false
    expect(instance.database_computed?).to be false
    expect(instance.cache_computed?).to be false
    
    result = instance.cache
    
    expect(instance.config_computed?).to be true
    expect(instance.database_computed?).to be true
    expect(instance.cache_computed?).to be true
    expect(result).to eq('Cache using Connected to: postgresql://localhost/test')
  end

  it 'handles dependencies accessed out of order' do
    instance = test_class.new
    
    # Access database first (should auto-resolve config)
    database_result = instance.database
    
    expect(instance.config_computed?).to be true
    expect(instance.database_computed?).to be true
    expect(database_result).to eq('Connected to: postgresql://localhost/test')
  end

  it 'detects circular dependencies' do
    circular_class = Class.new do
      extend LazyInit
      
      lazy_attr_reader :a, depends_on: [:b] do
        'value_a'
      end
      
      lazy_attr_reader :b, depends_on: [:a] do
        'value_b'
      end
    end

    instance = circular_class.new
    expect { instance.a }.to raise_error(LazyInit::DependencyError, /Circular dependency/)
  end

  it 'handles complex dependency chains' do
    complex_class = Class.new do
      extend LazyInit
      
      lazy_attr_reader :step1 do
        'step1_value'
      end
      
      lazy_attr_reader :step2, depends_on: [:step1] do
        "step2_using_#{step1}"
      end
      
      lazy_attr_reader :step3, depends_on: [:step1] do
        "step3_using_#{step1}"
      end
      
      lazy_attr_reader :final, depends_on: [:step2, :step3] do
        "final: #{step2} + #{step3}"
      end
    end

    instance = complex_class.new
    result = instance.final
    
    expect(result).to eq('final: step2_using_step1_value + step3_using_step1_value')
    expect(instance.step1_computed?).to be true
    expect(instance.step2_computed?).to be true
    expect(instance.step3_computed?).to be true
  end
end