require 'spec_helper'

describe PuppetFixtures::Fixtures do
  subject(:instance) { described_class.new(source_dir: source_dir) }

  let(:source_dir) { File.join('spec/fixtures/missing') }

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
