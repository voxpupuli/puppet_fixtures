# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name                 = 'puppet_fixtures'
  s.version              = '2.2.0'
  s.licenses             = ['GPL-2.0-only']
  s.summary              = 'Set up fixtures for Puppet testing'
  s.description          = <<~DESC
    Originally part of puppetlabs_spec_helper, but with a significant
    refactoring to make it available standalone.
  DESC
  s.authors               = ['Ewoud Kohl van Wijngaarden', 'Vox Pupuli']
  s.files                 = ['lib/puppet_fixtures.rb', 'lib/puppet_fixtures/tasks.rb', 'LICENSE']
  s.executables           = 'puppet-fixtures'
  s.homepage              = 'https://github.com/voxpupuli/puppet_fixtures'
  s.metadata              = { 'source_code_uri' => 'https://github.com/voxpupuli/puppet_fixtures' }
  s.required_ruby_version = '>= 3.2', '< 5'

  s.add_dependency 'logger', '< 2'
  s.add_dependency 'rake', '~> 13.0'
  s.add_development_dependency 'voxpupuli-rubocop', '~> 5.1.0'
end
