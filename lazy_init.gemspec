# frozen_string_literal: true

require_relative 'lib/lazy_init/version'

Gem::Specification.new do |spec|
  spec.name          = 'lazy_init'
  spec.version       = LazyInit::VERSION
  spec.authors       = ['Konstanty Koszewski']
  spec.email         = ['ka.koszewski@gmail.com']

  spec.summary       = 'Thread-safe lazy initialization patterns for Ruby'
  spec.description   = 'Provides thread-safe lazy initialization with clean, Ruby-idiomatic API. ' \
                       'Eliminates race conditions in lazy attribute initialization while maintaining performance.'
  spec.homepage      = 'https://github.com/N3BCKN/lazy_init'
  spec.license       = 'MIT'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/N3BCKN/lazy_init'
  spec.metadata['changelog_uri'] = 'https://github.com/N3BCKN/lazy_init/blob/main/CHANGELOG.md'
  spec.metadata['bug_tracker_uri'] = 'https://github.com/N3BCKN/lazy_init/issues'
  spec.metadata['documentation_uri'] = "https://rubydoc.info/gems/lazy_init/#{LazyInit::VERSION}"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end

  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 2.6'

  # Development dependencies
  spec.add_development_dependency 'benchmark-ips', '~> 2.10'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.12'
  spec.add_development_dependency 'rubocop', '~> 1.50.2'
  spec.add_development_dependency 'yard', '~> 0.9'
end
