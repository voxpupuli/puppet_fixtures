require_relative '../puppet_fixtures'

require 'rake'

namespace :fixtures do
  desc 'Create the fixtures directory'
  task :prep do
    PuppetFixtures.new.download
  end

  desc 'Clean up the fixtures directory'
  task :clean do
    PuppetFixtures.new.clean
  end
end
