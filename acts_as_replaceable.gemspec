Gem::Specification.new do |s|
  s.name = 'acts_as_replaceable'
  s.version = '1.1.0'
  s.date = %q{2013-09-03}
  s.email = 'technical@rrnpilot.org'
  s.homepage = 'http://github.com/rrn/acts_as_replaceable'
  s.summary = 'Overloads the create_or_update_without_callbacks method to allow duplicate records to be replaced without needing to always use find_or_create_by.'
  s.authors = ['Nicholas Jakobsen', 'Ryan Wallace']
  s.files = Dir.glob("{lib,spec}/**/*") + %w(README.rdoc)

  s.add_dependency('rails', '~> 4.0')
end
