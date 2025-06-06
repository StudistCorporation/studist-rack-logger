$:.push File.expand_path('lib', __dir__)

# Maintain your gem's version:
require 'studist/rack/logger/version'

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name = 'studist-rack-logger'
  s.version = Studist::Rack::Logger::VERSION
  s.authors = ['Studist Corporation']
  s.email = ['contact-dev@studist.jp']
  s.homepage = 'https://github.com/StudistCorporation/studist-rack-logger'
  s.summary = "Unified logging middleware for Rack applications with Configuration DSL and advanced filtering"
  s.description = 'A production-ready Rack middleware that provides structured JSON/LTSV logging with unified format across all Studist services. Features a powerful Configuration DSL, request sampling, advanced filtering, and 18 standardized fields including timestamp, trace_id, user information, and response metrics.'
  s.license = 'MIT'

  s.files = Dir['{lib}/**/*', 'LICENSE', 'Rakefile', 'README.md']

  s.required_ruby_version = '>= 3.0.0', '< 3.5.0'
  s.add_dependency 'json', '>= 2.0'
  s.add_dependency 'rack', '>= 2.0'
  s.test_files = Dir['spec/**/*']

  s.add_development_dependency 'bundler', '~> 2.0'
  s.add_development_dependency 'rake', '~> 13.0'
  s.add_development_dependency 'rspec', '~> 3.0'
  s.add_development_dependency 'rubocop', '~> 1.21'
  s.add_development_dependency 'rack-test', '~> 2.0'
  s.add_development_dependency 'yard', '~> 0.9'
  s.metadata = {
    'rubygems_mfa_required' => 'true',
  }
end
