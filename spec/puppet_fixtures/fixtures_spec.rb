require 'spec_helper'
require 'tmpdir'
require 'ostruct'

describe PuppetFixtures::Fixtures do
  subject(:instance) { described_class.new(source_dir: source_dir) }
  let(:fixtures) { described_class.new }

  let(:source_dir) { File.join('spec/fixtures/missing') }

  describe '#clean' do
  end

  describe '#download' do
    let(:logger) { double('Logger') }

    before do
      allow(instance).to receive(:logger).and_return(logger)
      allow(logger).to receive(:debug)
    end

    it do
      Dir.mktmpdir do |dir|
        target = File.join(dir, 'foo')
        allow(instance).to receive(:module_target_dir).and_return(target)
        instance.download

        expect(logger).to have_received(:debug).with("Downloading to #{target}")
        expect(logger).to have_received(:debug).with('No symlinks to create')
        expect(logger).to have_received(:debug).with('Nothing to download')
      end
    end
  end

  describe '#fixtures' do
    subject(:fixtures) { instance.fixtures }

    it { is_expected.to eq({ 'forge_modules' => {}, 'repositories' => {}, 'symlinks' => {} }) }
  end

  describe '#forge_modules' do
    subject(:forge_modules) { instance.forge_modules }

    it { is_expected.to eq({}) }
  end

  describe '#repositories' do
    subject(:repositories) { instance.repositories }

    it { is_expected.to eq({}) }
  end

  describe '#symlinks' do
    subject(:symlinks) { instance.symlinks }

    it { is_expected.to eq({}) }
  end

  describe '#include_repo?' do
    before do
      stub_const('Gem::Specification', Class.new do
        def self.find_by_name(name)
          case name
          when 'openvox'
            OpenStruct.new(version: '7.0.0')
          when 'puppet'
            OpenStruct.new(version: '6.0.0')
          else
            raise Gem::LoadError
          end
        end
      end)
      require 'semantic_puppet'
    end

    it 'returns true if version_range is nil' do
      expect(fixtures.send(:include_repo?, nil)).to eq(true)
    end

    it 'returns true if puppet version matches the range' do
      expect(fixtures.send(:include_repo?, '>= 6.0.0')).to eq(true)
    end

    it 'returns false if puppet version does not match the range' do
      expect(fixtures.send(:include_repo?, '< 6.0.0')).to eq(false)
    end

    it 'falls back to puppet gem if openvox is not found' do
      allow(Gem::Specification).to receive(:find_by_name).with('openvox').and_raise(Gem::LoadError)
      allow(Gem::Specification).to receive(:find_by_name).with('puppet').and_return(OpenStruct.new(version: '6.0.0'))
      expect(fixtures.send(:include_repo?, '>= 6.0.0')).to eq(true)
    end

    it 'raises if neither openvox nor puppet gem is found' do
      allow(Gem::Specification).to receive(:find_by_name).and_raise(Gem::LoadError)
      expect {
        fixtures.send(:include_repo?, '>= 6.0.0')
      }.to raise_error(RuntimeError, /Neither 'openvox' nor 'puppet' gem could be found/)
    end
  end
end
