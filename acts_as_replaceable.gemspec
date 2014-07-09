Gem::Specification.new do |s|
  s.name = 'acts_as_replaceable'
  s.version = '1.2.2'
  s.date = %q{2014-07-09}
  s.email = 'technical@rrnpilot.org'
  s.homepage = 'http://github.com/rrn/acts_as_replaceable'
  s.summary = 'Overloads the create_or_update_without_callbacks method to allow duplicate records to be replaced without needing to always use find_or_create_by.'
  s.authors = ['Nicholas Jakobsen', 'Ryan Wallace']
  s.files = Dir.glob("{lib,spec}/**/*") + %w(README.rdoc)

  s.add_dependency('rails', ">= 3.2", "<= 4.0.5")

  s.add_development_dependency('bundler')
  s.add_development_dependency('sqlite3')
  s.add_development_dependency('rspec-rails')
end
