require 'spec_helper'

describe PuppetFixtures do
  let(:instance) { described_class.new('source_dir') }

  describe '#fixtures' do
    before do
      allow(instance).to receive(:read_fixtures_file).and_return(fixtures_file)
      allow(instance).to receive(:module_target_dir).and_return('fixtures/modules')
    end

    context 'with empty fixtures' do
      let(:fixtures_file) { { 'fixtures' => {} } }

      context 'for symlinks' do
        before { allow(instance).to receive(:module_name).and_return('mymodule') }

        it { expect(instance.fixtures('symlinks')).to eq({ 'source_dir' => { branch: nil, flags: nil, ref: nil, scm: nil, subdir: nil, target: 'fixtures/modules/mymodule' } }) }
      end
    end
  end
end
