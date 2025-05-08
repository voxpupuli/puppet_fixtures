# frozen_string_literal: true

require_relative '../puppet_fixtures'

require 'rake'

namespace :fixtures do
  desc 'Create the fixtures directory'
  task :prep do
    PuppetFixtures::Fixtures.new(max_thread_limit: ENV.fetch('MAX_FIXTURE_THREAD_COUNT', 10).to_i).download
  end

  desc 'Clean up the fixtures directory'
  task :clean do
    PuppetFixtures::Fixtures.new.clean
  end
end
