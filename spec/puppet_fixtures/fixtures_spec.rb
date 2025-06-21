require 'spec_helper'
require 'tmpdir'

describe PuppetFixtures::Fixtures do
  subject(:instance) { described_class.new(source_dir: source_dir) }
  let(:fixtures) { described_class.new }

  let(:source_dir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(source_dir) }

  describe '#clean' do
  end

  describe '#download' do
    let(:logger) { double('Logger') }

    before do
      allow(instance).to receive(:logger).and_return(logger)
      allow(logger).to receive(:debug)
    end

    it 'runs without fixtures' do
      Dir.chdir(source_dir) do
        instance.download

        expect(logger).to have_received(:debug).with("Downloading to #{instance.module_target_dir}")
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

  describe '#gem_version' do
    it 'returns nil if a gem is not found' do
      expect(fixtures.send(:gem_version, 'does-not-exist')).to be_nil
    end

    it 'returns a string if a gem is found' do
      expect(fixtures.send(:gem_version, 'puppet_fixtures')).to be_instance_of(String)
    end
  end

  describe '#include_repo?' do
    it 'returns true if version_range is nil' do
      expect(fixtures).not_to receive(:gem_version)
      expect(fixtures.send(:include_repo?, nil)).to eq(true)
    end

    it 'returns true if puppet version matches the range' do
      expect(fixtures).to receive(:gem_version).with('openvox').and_return('7.0.0')
      expect(fixtures.send(:include_repo?, '>= 6.0.0')).to eq(true)
    end

    it 'returns false if puppet version does not match the range' do
      expect(fixtures).to receive(:gem_version).with('openvox').and_return('7.0.0')
      expect(fixtures.send(:include_repo?, '< 6.0.0')).to eq(false)
    end

    it 'falls back to puppet gem if openvox is not found' do
      expect(fixtures).to receive(:gem_version).with('openvox').and_return(nil)
      expect(fixtures).to receive(:gem_version).with('puppet').and_return('6.0.0')
      expect(fixtures.send(:include_repo?, '>= 6.0.0')).to eq(true)
    end

    it 'raises if neither openvox nor puppet gem is found' do
      expect(fixtures).to receive(:gem_version).with('openvox').and_return(nil)
      expect(fixtures).to receive(:gem_version).with('puppet').and_return(nil)
      expect {
        fixtures.send(:include_repo?, '>= 6.0.0')
      }.to raise_error(RuntimeError, /Neither 'openvox' nor 'puppet' gem could be found/)
    end
  end
end
