# frozen_string_literal: true

require 'json'
require 'open3'
require 'yaml'

# PuppetFixtures is a mechanism to download Puppet fixtures.
#
# These fixtures can be symlinks, repositories (git or Mercurial) or forge
# modules.
module PuppetFixtures
  # @return [Boolean]
  #   true if the os is a windows system
  def self.windows?
    # Ruby only sets File::ALT_SEPARATOR on Windows and Rubys standard library
    # uses this to check for Windows
    !!File::ALT_SEPARATOR
  end

  class Fixtures
    attr_reader :source_dir

    def initialize(source_dir: Dir.pwd, max_thread_limit: 10)
      @source_dir = source_dir
      @max_thread_limit = max_thread_limit
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
      @repositories ||= fixtures['repositories']
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
      @forge_modules ||= fixtures['forge_modules']
    end

    # @return [Hash[String, Symlink]]
    #   A hash of symlinks specified in the fixtures file
    def symlinks
      @symlinks ||= fixtures['symlinks']
    end

    def fixtures
      @fixtures ||= begin
        categories = read_fixtures_file['fixtures']

        categories['symlinks'] ||= begin
          metadata = PuppetFixtures::Metadata.new(File.join(source_dir, 'metadata.json'))
          { metadata.name.split('-').last => source_dir }
        rescue ArgumentError
          {}
        end
        categories['forge_modules'] ||= {}
        categories['repositories'] ||= {}

        defaults = { 'target' => module_target_dir }

        %w[symlinks forge_modules repositories].to_h do |category|
          # load defaults from the `.fixtures.yml` `defaults` section
          # for the requested category and merge them into my defaults
          category_defaults = if (category_defaults = categories.dig('defaults', category))
                                defaults.merge(category_defaults)
                              else
                                defaults
                              end

          entries = categories[category].to_h do |fixture, opts|
            # convert a simple string fixture to a hash, by
            # using the string fixture as the `repo` option of the hash.
            opts = { 'repo' => opts } if opts.instance_of?(String)
            # there should be a warning or something if it's not a hash...
            next unless opts.instance_of?(Hash)

            # merge our options into the defaults to get the
            # final option list
            opts = category_defaults.merge(opts)

            next unless include_repo?(opts['puppet_version'])

            entry = validate_fixture_hash!(
              target: File.join(opts['target'], fixture),
              ref: opts['ref'] || opts['tag'],
              branch: opts['branch'],
              scm: opts.fetch('scm', 'git'),
              flags: opts['flags'],
              subdir: opts['subdir'],
            )

            case category
            when 'forge_modules'
              entry.delete(:scm)
              entry.delete(:branch)
              entry.delete(:subdir)
            when 'symlinks'
              entry = PuppetFixtures::Symlink.new(link: entry[:target], target: opts['repo'])
            end

            [opts['repo'], entry]
          end

          [category, entries]
        end
      end
    end

    # @param [String] remote
    #   The remote url or namespace/name of the module to download
    # @param [String] scm
    #   The SCM to use
    # @return [Boolean]
    #   Returns true if the module was downloaded successfully, false otherwise
    def download_repository(remote, target:, scm:, subdir:, ref:, branch:, flags:)
      repository = PuppetFixtures::Repository.factory(scm: scm, remote: remote, target: target, branch: branch, ref: ref)
      repository.download(flags, subdir)
    end

    # @return [String]
    #   the spec/fixtures/modules directory in the module root folder
    def module_target_dir
      # TODO: relative to source_dir?
      @module_target_dir ||= File.expand_path(File.join('spec', 'fixtures', 'modules'))
    end

    # @param [String] remote
    #   the remote url or namespace/name of the module to download
    # @return [Boolean]
    #   returns true if the module was downloaded, false otherwise
    def download_module(remote, ref:, target:, flags:)
      if File.directory?(target)
        if !ref || ref.empty?
          logger.debug("Module #{target} already up to date")
          return false
        end

        begin
          version = PuppetFixtures::Metadata.new(File.join(target, 'metadata.json')).version
        rescue ArgumentError
          logger.warn "Unable to detect module version for #{target}; updating"
        else
          if ref == version
            logger.debug("Module #{target} already up to date (#{ref})")
            return false
          else
            logger.debug("Module #{target} version #{version} != #{ref}; updating")
          end
        end
      end

      command = %w[puppet module install]
      command << '--version' << ref if ref
      command += flags if flags
      command += ['--ignore-dependencies', '--force', '--target-dir', module_target_dir, remote]

      unless run_command(command)
        raise "Failed to install module #{remote} to #{module_target_dir}"
      end

      true
    end

    def download
      logger.debug("Downloading to #{module_target_dir}")
      FileUtils.mkdir_p(module_target_dir)

      if symlinks.empty?
        logger.debug('No symlinks to create')
      else
        symlinks.each_value do |symlink|
          logger.info("Creating symlink #{symlink}")
          symlink.create
        end
      end

      queue = Queue.new

      repositories.each do |remote, opts|
        queue << [:repository, remote, opts]
      end
      forge_modules.each do |remote, opts|
        queue << [:forge, remote, opts]
      end

      if queue.empty?
        logger.debug('Nothing to download')
        return
      end

      instance = self

      thread_count = [@max_thread_limit, queue.size].min
      logger.debug("Download queue size: #{queue.size}; using #{thread_count} threads")

      threads = Array.new(thread_count) do |_i|
        Thread.new do
          loop do
            begin
              type, remote, opts = queue.pop(true)
            rescue ThreadError
              break # Queue is empty
            end
            case type
            when :repository
              instance.download_repository(remote, **opts)
            when :forge
              instance.download_module(remote, **opts)
            end
          end
        end
      end

      begin
        threads.map(&:join)
      rescue Interrupt
        # pass
      end
    end

    def clean
      repositories.each_value do |opts|
        target = opts[:target]
        logger.debug("Removing repository #{target}")
        FileUtils.rm_rf(target)
      end

      forge_modules.each_value do |opts|
        target = opts[:target]
        logger.debug("Removing forge module #{target}")
        FileUtils.rm_rf(target)
      end

      symlinks.each_value do |symlink|
        logger.debug("Removing symlink #{symlink}")
        symlink.remove
      end
    end

    def fixture_path
      if ENV['FIXTURES_YML']
        ENV['FIXTURES_YML']
      elsif File.exist?('.fixtures.yml')
        '.fixtures.yml'
      elsif File.exist?('.fixtures.yaml')
        '.fixtures.yaml'
      end
    end

    private

    def gem_version(name)
      Gem::Specification.find_by_name(name).version.to_s
    rescue Gem::LoadError
      nil
    end

    def include_repo?(version_range)
      return true unless version_range

      puppet_version = gem_version('openvox') || gem_version('puppet')
      raise "Neither 'openvox' nor 'puppet' gem could be found. Please install one of them." unless puppet_version

      require 'semantic_puppet'

      puppet_version = SemanticPuppet::Version.parse(puppet_version)
      constraint = SemanticPuppet::VersionRange.parse(version_range)
      constraint.include?(puppet_version)
    end

    def git_remote_url(target)
      output, status = Open3.capture2e('git', '--git-dir', File.join(target, '.git'), 'ls-remote', '--get-url', 'origin')
      status.success? ? output.strip : nil
    end

    # creates a logger so we can log events with certain levels
    def logger
      @logger ||= begin
        require 'logger'
        Logger.new($stderr, level: ENV['ENABLE_LOGGER'] ? Logger::DEBUG : Logger::INFO)
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
      if hash[:flags].is_a?(String)
        require 'shellwords'
        hash[:flags] = Shellwords.split(hash[:flags])
      end

      if hash['scm'] == 'git' && hash['ref'].include?('/')
        # Forward slashes in the ref aren't allowed. And is probably a branch name.
        raise ArgumentError, "The ref for #{hash['target']} is invalid (Contains a forward slash). If this is a branch name, please use the 'branch' setting instead."
      end

      hash
    end

    # @param [Array[String]] command
    def run_command(command, chdir: nil)
      logger.debug do
        require 'shellwords'
        if chdir
          "Calling command #{Shellwords.join(command)} in #{chdir}"
        else
          "Calling command #{Shellwords.join(command)}"
        end
      end
      if chdir
        system(*command, chdir: chdir)
      else
        system(*command)
      end
    end
  end

  class Metadata
    def initialize(path)
      raise ArgumentError unless File.file?(path) && File.readable?(path)

      @metadata = JSON.parse(File.read(path))
    rescue JSON::ParserError => e
      raise ArgumentError, "Failed to read module metadata at #{path}: #{e}"
    end

    # @return [String[1]] The module name
    def name
      n = @metadata['name']
      raise ArgumentError 'No module name found' if !n || n.empty?

      n
    end

    # @return [String[1]] The module version
    def version
      v = @metadata['version']
      raise ArgumentError 'No module name found' if !v || v.empty?

      v
    end
  end

  class Symlink
    # @param target [String]
    #   the target directory
    # @param link [String]
    #   the name of the link you wish to create
    def initialize(target:, link:)
      @target = target
      @link = link
    end

    # Create a junction on Windows or otherwise a symlink
    # works on windows and linux
    def create
      return if File.symlink?(@link)

      if PuppetFixtures.windows?
        begin
          require 'win32/dir'
        rescue LoadError
          # the require only works on windows
        end
        target = File.join(File.dirname(@link), @target) unless Pathname.new(@target).absolute?
        if Dir.respond_to?(:create_junction)
          Dir.create_junction(@link, target)
        else
          warn 'win32-dir gem not installed, falling back to executing mklink directly'
          # TODO: use run_command
          system("call mklink /J \"#{@link.tr('/', '\\')}\" \"#{target.tr('/', '\\')}\"")
        end
      else
        FileUtils.ln_sf(@target, @link)
      end
    end

    def remove
      FileUtils.rm_f(@link)
    end

    def to_s
      # TODO: relative?
      "#{@link} => #{@target}"
    end
  end

  module Repository
    def self.factory(scm:, remote:, target:, branch:, ref:)
      cls = case scm
            when 'git'
              Repository::Git
            when 'hg'
              Repository::Mercurial
            else
              raise ArgumentError, "Unfortunately #{scm} is not supported yet"
            end
      cls.new(remote: remote, target: target, branch: branch, ref: ref)
    end

    class Base
      def initialize(remote:, target:, branch:, ref:)
        @remote = remote
        @target = target
        @ref = ref
        @branch = branch
      end

      def download(flags = nil, subdir = nil)
        can_update = false
        if File.directory?(@target)
          if remote_url_changed?
            warn "Remote for #{@target} has changed, recloning repository"
            FileUtils.rm_rf(@target)
          else
            can_update = true
          end
        end

        if can_update
          update
        else
          clone(flags)
          unless File.exist?(@target)
            raise "Failed to clone repository #{@remote} into #{@target}"
          end
        end

        revision
        remove_subdirectory(subdir) if subdir
      end

      protected

      def remove_subdirectory(subdir)
        Dir.mktmpdir do |tmpdir|
          FileUtils.mv(Dir.glob(File.join(@target, subdir, '{.[^.]*,*}')), tmpdir)
          FileUtils.rm_rf(File.join(@target, subdir))
          FileUtils.mv(Dir.glob(File.join(tmpdir, '{.[^.]*,*}')), @target.to_s)
        end
      end

      def run_command(command, chdir: nil)
        # TODO: duplicated
        logger.debug do
          require 'shellwords'
          if chdir
            "Calling command #{Shellwords.join(command)} in #{chdir}"
          else
            "Calling command #{Shellwords.join(command)}"
          end
        end
        if chdir
          system(*command, chdir: chdir)
        else
          system(*command)
        end
      end

      def logger
        # TODO: duplicated
        @logger ||= begin
          require 'logger'
          # TODO: progname?
          Logger.new($stderr, level: ENV['ENABLE_LOGGER'] ? Logger::DEBUG : Logger::INFO)
        end
      end
    end

    class Git < Base
      def clone(flags = nil)
        command = %w[git clone]
        command.push('--depth', '1') unless @ref
        command.push('-b', @branch) if @branch
        command.push(flags) if flags
        command.push(@remote, @target)

        run_command(command)
      end

      def update
        # TODO: should this pull?
        command = %w[git fetch]
        command.push('--unshallow') if shallow_git_repo?

        run_command(command, chdir: @target)
      end

      def revision
        return true unless @ref

        command = ['git', 'reset', '--hard', @ref]
        result = run_command(command, chdir: @target)
        raise "Invalid ref #{@ref} for #{@target}" unless result

        result
      end

      def remote_url_changed?(remote = 'origin')
        remote_url(remote) != @remote
      end

      private

      def remote_url(remote = 'origin')
        output, status = Open3.capture2e('git', '--git-dir', File.join(@target, '.git'), 'ls-remote', '--get-url', remote)
        status.success? ? output.strip : nil
      end

      def shallow_git_repo?
        File.file?(File.join(@target, '.git', 'shallow'))
      end
    end

    class Mercurial < Base
      def clone(flags = nil)
        command = %w[hg clone]
        command.push('-b', @branch) if @branch
        command.push(flags) if flags
        command.push(@remote, @target)

        run_command(command)
      end

      def update
        run_command(%w[hg pull])
      end

      def revision
        return true unless @ref

        command = ['hg', 'update', '--clean', '-r', @ref]
        result = run_command(command, chdir: @target)
        raise "Invalid ref #{@ref} for #{@target}" unless result

        result
      end

      def remote_url_changed?
        # Not implemented
        false
      end
    end
  end
end
