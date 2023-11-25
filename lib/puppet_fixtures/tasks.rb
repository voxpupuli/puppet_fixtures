require_relative '../puppet_fixtures'

require 'rake'

namespace :fixtures do
  desc 'Create the fixtures directory'
  task :prep do
    PuppetFixtures.new.download(max_thread_limit: ENV.fetch('MAX_FIXTURE_THREAD_COUNT', 10).to_i)
  end

  desc 'Clean up the fixtures directory'
  task :clean do
    PuppetFixtures.new.clean
  end
end
