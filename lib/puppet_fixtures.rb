# frozen_string_literal: true

require 'json'
require 'open3'
require 'yaml'

class PuppetFixtures
  attr_reader :source_dir

  # @return [Boolean]
  #   true if the os is a windows system
  def self.windows?
    # Ruby only sets File::ALT_SEPARATOR on Windows and Rubys standard library
    # uses this to check for Windows
    !!File::ALT_SEPARATOR
  end

  def initialize(source_dir = Dir.pwd)
    @source_dir = source_dir
  end

  # @return [Hash]
  #   A hash of all the fixture repositories
  # @example
  #   {
  #     "puppetlabs-stdlib"=>{
  #       "target"=>"https://gitlab.com/puppetlabs/puppet-stdlib.git",
  #       "ref"=>nil,
  #       "branch"=>"main",
  #       "scm"=>nil,
  #     }
  #   }
  def repositories
    @repositories ||= fixtures('repositories') || {}
  end

  # @return [Hash]
  #    A hash of all the fixture forge modules
  # @example
  #   {
  #     "puppetlabs-stdlib"=>{
  #       "target"=>"spec/fixtures/modules/stdlib",
  #       "ref"=>nil,
  #       "branch"=>nil,
  #       "scm"=>nil,
  #       "flags"=>"--module_repository=https://myforge.example.com/",
  #       "subdir"=>nil,
  #     }
  #   }
  def forge_modules
    @forge_modules ||= fixtures('forge_modules') || {}
  end

  # @return [Hash]
  #   A hash of symlinks specified in the fixtures file
  def symlinks
    @symlinks ||= fixtures('symlinks') || {}
  end

  def fixtures(category)
    fixtures = read_fixtures_file['fixtures']

    if fixtures['symlinks'].nil?
      fixtures['symlinks'] = { module_name => source_dir }
    end

    result = {}

    if fixtures[category]
      defaults = { 'target' => module_target_dir }

      # load defaults from the `.fixtures.yml` `defaults` section
      # for the requested category and merge them into my defaults
      if (category_defaults = fixtures.dig('defaults', category))
        defaults.merge!(category_defaults)
      end

      fixtures[category].each do |fixture, opts|
        # convert a simple string fixture to a hash, by
        # using the string fixture as the `repo` option of the hash.
        if opts.instance_of?(String)
          opts = { 'repo' => opts }
        end
        # there should be a warning or something if it's not a hash...
        next unless opts.instance_of?(Hash)

        # merge our options into the defaults to get the
        # final option list
        opts = defaults.merge(opts)

        next unless include_repo?(opts['puppet_version'])

        result[opts['repo']] = validate_fixture_hash!(
          target: File.join(opts['target'], fixture),
          ref: opts['ref'] || opts['tag'],
          branch: opts['branch'],
          scm: opts['scm'],
          flags: opts['flags'],
          subdir: opts['subdir'],
        )
      end
    end

    result
  end

  # @summary The limit on the amount threads used.
  #
  # Defaults to 10, but the MAX_FIXTURE_THREAD_COUNT can be used to set this
  # limit.
  #
  # @return [Integer]
  def max_thread_limit
    ENV.fetch('MAX_FIXTURE_THREAD_COUNT', 10).to_i
  end

  # Create a junction on Windows or otherwise a symlink
  # works on windows and linux
  # @param target [String]
  #   the target directory
  # @param link [String]
  #   the name of the link you wish to create
  def setup_symlink(target, link)
    return if File.symlink?(link)

    logger.info("Creating symlink from #{link} to #{target}")
    if PuppetFixtures.windows?
      begin
        require 'win32/dir'
      rescue LoadError
      end
      target = File.join(File.dirname(link), target) unless Pathname.new(target).absolute?
      if Dir.respond_to?(:create_junction)
        Dir.create_junction(link, target)
      else
        warn 'win32-dir gem not installed, falling back to executing mklink directly'
        system("call mklink /J \"#{link.tr('/', '\\')}\" \"#{target.tr('/', '\\')}\"")
      end
    else
      FileUtils.ln_sf(target, link)
    end
  end

  # @param [String] remote
  #   The remote url or namespace/name of the module to download
  # @param [String] scm
  #   The SCM to use
  # @return [Boolean]
  #   Returns true if the module was downloaded successfully, false otherwise
  def download_repository(remote, target:, scm: 'git', subdir: nil, ref: nil, branch: nil, flags: [])
    if valid_repo?(scm, target, remote)
      update_repo(scm, target)
    else
      clone_repo(scm, remote, target, subdir, ref, branch, flags)
    end
    revision(scm, target, ref) if ref
    remove_subdirectory(target, subdir) if subdir
  end

  # @return [String]
  #   the spec/fixtures/modules directory in the module root folder
  def module_target_dir
    @module_target_dir ||= File.expand_path(File.join('spec', 'fixtures', 'modules'))
  end

  # @param [String] remote
  #   the remote url or namespace/name of the module to download
  # @return [Boolean]
  #   returns true if the module was downloaded, false otherwise
  def download_module(remote, ref: nil, target: nil, flags: [])
    return false if File.directory?(target) && (ref.empty? || ref == module_version(target))

    command = ['puppet', 'module', 'install']
    command << '--version' << ref if ref
    command += flags
    command += ['--ignore-dependencies', '--force', '--target-dir', module_target_dir, remote]

    unless system(*command)
      raise "Failed to install module #{remote} to #{module_target_dir}"
    end

    true
  end

  def download
    FileUtils.mkdir_p(module_target_dir)

    symlinks.each do |target, link|
      setup_symlink(target, link['target'])
    end

    queue = Queue.new

    repositories.each do |remote, opts|
      queue << [:repository, remote, opts]
    end
    forge_modules.each do |remote, opts|
      queue << [:forge, remote, opts]
    end

    return if queue.empty?

    threads = [max_thread_limit, queue.size].min.times.map do |i|
      Thread.new do
        type, remote, opts = queue.pop(true)
        case type
        when :repository
          fixtures.download_repository(remote, **opts)
        when :forge
          fixtures.download_module(remote, **opts)
        end
      end
    end

    threads.each { thread.join }
  end

  def clean
    repositories.each do |_remote, opts|
      target = opts['target']
      FileUtils.rm_rf(target)
    end

    forge_modules.each do |_remote, opts|
      target = opts['target']
      FileUtils.rm_rf(target)
    end

    symlinks.each do |_source, opts|
      target = opts['target']
      FileUtils.rm_f(target)
    end
  end

  private

  def clone_repo(scm, remote, target, _subdir = nil, ref = nil, branch = nil, flags = nil)
    command = [scm]
    case scm
    when 'hg'
      command.push('clone')
      command.push('-b', branch) if branch
      command.push(flags) if flags
      command.push(remote, target)
    when 'git'
      command.push('clone')
      command.push('--depth 1') unless ref
      command.push('-b', branch) if branch
      command.push(flags) if flags
      command.push(remote, target)
    else
      raise "Unfortunately #{scm} is not supported yet"
    end
    result = system(*command)
    unless File.exist?(target)
      raise "Failed to clone #{scm} repository #{remote} into #{target}"
    end

    result
  end

  def update_repo(scm, target)
    command = [scm]
     case scm
     when 'hg'
       command.push('pull')
     when 'git'
       # TODO: should this pull?
       command.push('fetch')
       command.push('--unshallow') if shallow_git_repo?
     else
       raise "Unfortunately #{scm} is not supported yet"
     end
    system(*command, chdir: target)
  end

  def revision(scm, target, ref)
    command = [scm]
    case scm
    when 'hg'
      command.push('update', '--clean', '-r', ref)
    when 'git'
      command.push('reset', '--hard', ref)
    else
      raise "Unfortunately #{scm} is not supported yet"
    end
    result = system(*command, chdir: target)
    raise "Invalid ref #{ref} for #{target}" unless result
  end

  def read_metadata(path)
    raise ArgumentError unless File.file?(path) && File.readable?(path)

    JSON.parse(File.read('metadata.json'))
  end

  # @return [String]
  #   the name of current module
  def module_name
    metadata = read_metadata(File.join(source_dir, 'metadata.json'))
    metadata_name = metadata.fetch('name', nil) || ''

    raise ArgumentError if metadata_name.empty?

    metadata_name.split('-').last
  rescue JSON::ParserError, ArgumentError
    File.basename(source_dir).split('-').last
  end

  def module_version(path)
    metadata = read_metadata(File.join(path, 'metadata.json'))
    metadata.fetch('version', '0.0.1')
  rescue JSON::ParserError, ArgumentError
    logger.warn "Failed to find module version at path #{path}"
    '0.0.1'
  end

  def shallow_git_repo?
    File.file?(File.join('.git', 'shallow'))
  end

  def include_repo?(version_range)
    return true unless version_range

    require 'semantic_puppet'

    puppet_spec = Gem::Specification.find_by_name('puppet')
    puppet_version = SemanticPuppet::Version.parse(puppet_spec.version.to_s)

    constraint = SemanticPuppet::VersionRange.parse(version_range)
    constraint.include?(puppet_version)
  end

  def valid_repo?(scm, target, remote)
    return false unless File.directory?(target)

    if scm == 'git' && git_remote_url(target) != remote
      warn "Git remote for #{target} has changed, recloning repository"
      FileUtils.rm_rf(target)
      return false
    end

    true
  end

  def git_remote_url(target)
    output, status = Open3.capture2e('git', '--git-dir', File.join(target, '.git'), 'ls-remote', '--get-url', 'origin')
    status.success? ? output.strip : nil
  end

  def remove_subdirectory(target, subdir)
    return if subdir.nil?

    Dir.mktmpdir do |tmpdir|
      FileUtils.mv(Dir.glob(File.join(target, subdir, "{.[^\.]*,*}")), tmpdir)
      FileUtils.rm_rf(File.join(target, subdir))
      FileUtils.mv(Dir.glob(File.join(tmpdir, "{.[^\.]*,*}")), target.to_s)
    end
  end

  # creates a logger so we can log events with certain levels
  def logger
    @logger ||= begin
      require 'logger'
      Logger.new($stderr, level: ENV['ENABLE_LOGGER'] ? Logger::DEBUG : Logger::INFO)
    end
  end

  def fixture_path
    if ENV['FIXTURES_YML']
      ENV['FIXTURES_YML']
    elsif File.exist?('.fixtures.yml')
      '.fixtures.yml'
    elsif File.exist?('.fixtures.yaml')
      '.fixtures.yaml'
    else
      nil
    end
  end

  def read_fixtures_file
    fixtures_yaml = fixture_path

    fixtures = nil
    if fixtures_yaml
      begin
        fixtures = YAML.load_file(fixtures_yaml)
      rescue Errno::ENOENT
        raise "Fixtures file not found: '#{fixtures_yaml}'"
      rescue Psych::SyntaxError => e
        raise "Found malformed YAML in '#{fixtures_yaml}' on line #{e.line} column #{e.column}: #{e.problem}"
      end
    end
    fixtures ||= { 'fixtures' => {} }

    unless fixtures.include?('fixtures')
      # File is non-empty, but does not specify fixtures
      raise("No 'fixtures' entries found in '#{fixtures_yaml}'; required")
    end

    fixtures
  end

  def validate_fixture_hash!(**hash)
    if hash['flags'].is_a?(String)
      require 'shellwords'
      hash['flags'] = Shellwords.split(hash['flags'])
    end

    if hash['scm'] == 'git' && hash['ref'].include?('/')
      # Forward slashes in the ref aren't allowed. And is probably a branch name.
      raise ArgumentError, "The ref for #{hash['target']} is invalid (Contains a forward slash). If this is a branch name, please use the 'branch' setting instead."
    end

    hash
  end
end
