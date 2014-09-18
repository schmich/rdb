require File.expand_path('lib/rdb/version.rb', File.dirname(__FILE__))

Gem::Specification.new do |s|
  s.name = 'rdb'
  s.version = Rdb::VERSION
  s.bindir = 'bin'
  s.executables = ['rdb']
  s.date = Time.now.strftime('%Y-%m-%d')
  s.summary = 'Browser-based cross-platform Ruby 2.x debugger.'
  s.description = 'Browser-based cross-platform Ruby 2.x debugger. Includes breakpoints, expression evaluation, call stacks, error handling, and remote debugging.'
  s.authors = ['Chris Schmich']
  s.email = 'schmch@gmail.com'
  s.files = `git ls-files`.split("\n")
  s.require_path = 'lib'
  s.homepage = 'https://github.com/schmich/rdb'
  s.license = 'MIT'
  s.required_ruby_version = '>= 2.0.0'
  s.add_runtime_dependency 'byebug', '~> 3.4.0'
  s.add_runtime_dependency 'sinatra', '~> 1.4.5'
  s.add_runtime_dependency 'sinatra-contrib', '~> 1.4.2'
  s.add_runtime_dependency 'sinatra-sse', '~> 0.1'
  s.add_runtime_dependency 'msgpack', '~> 0.5.8'
  s.add_runtime_dependency 'cod', '~> 0.5.0'
  s.add_runtime_dependency 'thin', '~> 1.4.1'
  s.add_development_dependency 'rake', '~> 10.3.2'
end
