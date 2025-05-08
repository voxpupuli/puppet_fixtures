Gem::Specification.new do |s|
  s.name                 = 'puppet_fixtures'
  s.version              = '0.1.0'
  s.licenses             = ['GPL-2.0-only']
  s.summary              = 'Set up fixtures for Puppet testing'
  s.description          = <<~DESC
    Originally part of puppetlabs_spec_helper, but with a significant
    refactoring to make it available standalone.
  DESC
  s.authors               = ['Ewoud Kohl van Wijngaarden']
  s.files                 = ['lib/puppet_fixtures.rb', 'lib/puppet_fixtures/tasks.rb', 'LICENSE']
  s.executables           << 'puppet-fixtures'
  s.homepage              = 'https://github.com/voxpupuli/puppet_fixtures'
  s.metadata              = { 'source_code_uri' => 'https://github.com/voxpupuli/puppet_fixtures' }
  s.required_ruby_version = '>= 2.7', '< 4'

  s.add_dependency 'rake', '~> 13.0'
end
