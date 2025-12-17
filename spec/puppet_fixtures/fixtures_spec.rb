# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

describe PuppetFixtures::Fixtures do
  subject(:instance) { described_class.new(source_dir: source_dir) }

  let(:fixtures) { described_class.new }

  let(:source_dir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(source_dir) }

  # TODO: Implement tests
  # describe '#clean' do
  # end

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

    it 'downloads more than the max thread count' do
      Dir.chdir(source_dir) do
        count = instance.instance_variable_get(:@max_thread_limit) + 1
        fixtures = { 'fixtures' => { 'repositories' => count.times.to_h { |n| ["source#{n}", "target#{n}"] } } }
        File.write(File.join(source_dir, '.fixtures.yml'), fixtures.to_yaml)

        expect(instance.repositories.size).to eq(count)

        allow(instance).to receive(:download_repository)

        instance.download

        expect(instance).to have_received(:download_repository).exactly(count).times
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
      expect(fixtures.send(:include_repo?, nil)).to be(true)
    end

    it 'returns true if puppet version matches the range' do
      expect(fixtures).to receive(:gem_version).with('openvox').and_return('7.0.0')
      expect(fixtures.send(:include_repo?, '>= 6.0.0')).to be(true)
    end

    it 'returns false if puppet version does not match the range' do
      expect(fixtures).to receive(:gem_version).with('openvox').and_return('7.0.0')
      expect(fixtures.send(:include_repo?, '< 6.0.0')).to be(false)
    end

    it 'falls back to puppet gem if openvox is not found' do
      expect(fixtures).to receive(:gem_version).with('openvox').and_return(nil)
      expect(fixtures).to receive(:gem_version).with('puppet').and_return('6.0.0')
      expect(fixtures.send(:include_repo?, '>= 6.0.0')).to be(true)
    end

    it 'raises if neither openvox nor puppet gem is found' do
      expect(fixtures).to receive(:gem_version).with('openvox').and_return(nil)
      expect(fixtures).to receive(:gem_version).with('puppet').and_return(nil)
      expect do
        fixtures.send(:include_repo?, '>= 6.0.0')
      end.to raise_error(RuntimeError, /Neither 'openvox' nor 'puppet' gem could be found/)
    end
  end

  describe '#deep_expand_env' do
    around do |example|
      old_env = ENV.to_hash
      # old_env = ENV.dup
      example.run
    ensure
      ENV.replace(old_env)
    end

    context 'with strings' do
      it 'with a single variable' do
        ENV['SINGLE_VAR'] = 'single_value'
        input = 'This is a ${SINGLE_VAR}'
        expected_output = 'This is a single_value'

        output = PuppetFixtures.deep_expand_env(input)
        expect(output).to eq(expected_output)
      end

      it 'with multiple variables' do
        ENV['VAR_A'] = 'valueA'
        ENV['VAR_B'] = 'valueB'
        input = 'Values: ${VAR_A} and ${VAR_B}'
        expected_output = 'Values: valueA and valueB'

        output = PuppetFixtures.deep_expand_env(input)
        expect(output).to eq(expected_output)
      end

      it 'with invalid variables' do
        input = 'This is an ${INVALID_VAR}'
        expected_output = 'This is an ${INVALID_VAR}'

        output = PuppetFixtures.deep_expand_env(input)
        expect(output).to eq(expected_output)
      end
    end

    context 'with arrays' do
      it 'with a single variable' do
        input = ['Item 1', 'Item with ${ARRAY_VAR}', 'Item 3']
        ENV['ARRAY_VAR'] = 'array_value'
        expected_output = ['Item 1', 'Item with array_value', 'Item 3']
        output = PuppetFixtures.deep_expand_env(input)
        expect(output).to eq(expected_output)
      end

      it 'with multiple variables' do
        input = ['${VAR1}', '${VAR2}', 'No var here']
        ENV['VAR1'] = 'value1'
        ENV['VAR2'] = 'value2'
        expected_output = ['value1', 'value2', 'No var here']
        output = PuppetFixtures.deep_expand_env(input)
        expect(output).to eq(expected_output)
      end

      it 'with nested arrays' do
        input = ['Level 1', ['Level 2 with ${NESTED_VAR}']]
        ENV['NESTED_VAR'] = 'nested_value'
        expected_output = ['Level 1', ['Level 2 with nested_value']]
        output = PuppetFixtures.deep_expand_env(input)
        expect(output).to eq(expected_output)
      end

      it 'with invalid variables' do
        input = ['Item with ${INVALID_VAR}', 'Another item']
        expected_output = ['Item with ${INVALID_VAR}', 'Another item']
        output = PuppetFixtures.deep_expand_env(input)
        expect(output).to eq(expected_output)
      end
    end

    context 'with hashes' do
      it 'with a single variable' do
        input = { 'key1' => 'Value with ${HASH_VAR}', 'key2' => 'Another value' }
        ENV['HASH_VAR'] = 'hash_value'
        expected_output = { 'key1' => 'Value with hash_value', 'key2' => 'Another value' }
        output = PuppetFixtures.deep_expand_env(input)
        expect(output).to eq(expected_output)
      end

      it 'with multiple variables' do
        input = { 'key1' => '${VAR1}', 'key2' => '${VAR2}' }
        ENV['VAR1'] = 'value1'
        ENV['VAR2'] = 'value2'
        expected_output = { 'key1' => 'value1', 'key2' => 'value2' }
        output = PuppetFixtures.deep_expand_env(input)
        expect(output).to eq(expected_output)
      end

      it 'with invalid variables' do
        input = { 'key1' => 'Value with ${INVALID_VAR}', 'key2' => 'Another value' }
        expected_output = { 'key1' => 'Value with ${INVALID_VAR}', 'key2' => 'Another value' }
        output = PuppetFixtures.deep_expand_env(input)
        expect(output).to eq(expected_output)
      end

      it 'with nested structures' do
        input = {
          'level1' => {
            'level2' => [
              'Value with ${VAR1}',
              { 'level3_key' => 'Another value with ${VAR2}' },
            ],
          },
        }

        ENV['VAR1'] = 'expanded1'
        ENV['VAR2'] = 'expanded2'

        expected_output = {
          'level1' => {
            'level2' => [
              'Value with expanded1',
              { 'level3_key' => 'Another value with expanded2' },
            ],
          },
        }

        output = PuppetFixtures.deep_expand_env(input)
        expect(output).to eq(expected_output)
      end
    end

    it 'leaves non-string values unchanged' do
      input = {
        'number' => 42,
        'boolean' => true,
        'nil_value' => nil,
        'array' => [1, 2, 3],
      }

      output = PuppetFixtures.deep_expand_env(input)
      expect(output).to eq(input)
    end
  end
end
