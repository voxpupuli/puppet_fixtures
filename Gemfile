source 'https://rubygems.org'

gemspec

gem 'openvox', '>= 7'

group :test do
  gem 'rspec', require: false
end

group :development do
  gem 'yard'
end

group :release, optional: true do
  gem 'faraday-retry', '~> 2.1', require: false
  gem 'github_changelog_generator', '~> 1.16.4', require: false
end
