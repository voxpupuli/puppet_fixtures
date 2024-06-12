require 'spec_helper'
require 'tmpdir'

describe PuppetFixtures::Fixtures do
  subject(:instance) { described_class.new(source_dir: source_dir) }

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
end
