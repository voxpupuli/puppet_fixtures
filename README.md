# puppet_fixtures

Puppet module developers use a `.fixtures.yml` file to describe which resources to use during testing.
This is a standalone implementation that improves [puppetlabs_spec_helper](https://github.com/puppetlabs/puppetlabs_spec_helper) by using better parallelization.

## Usage

Add `puppet_fixtures` to your `Gemfile`:

```ruby
gem 'puppet_fixtures'
```

Now you can use `bundle exec puppet-fixtures`, for example:
```console
$ bundle exec puppet-fixtures show
Parsing .fixtures.yml

Symlinks
  /home/ekohl/dev/puppet-example/spec/fixtures/modules/example => /home/ekohl/dev/puppet-example

Repositories
  stdlib => git+https://github.com/puppetlabs/puppetlabs-stdlib
$ bundle exec puppet-fixtures install
I, [2025-05-08T13:14:33.084643 #79391]  INFO -- : Creating symlink /home/ekohl/dev/puppet-example/spec/fixtures/modules/example => /home/ekohl/dev/puppet-example
Cloning into '/home/ekohl/dev/puppet-example/spec/fixtures/modules/stdlib'...
remote: Enumerating objects: 472, done.
remote: Counting objects: 100% (472/472), done.
remote: Compressing objects: 100% (399/399), done.
remote: Total 472 (delta 99), reused 223 (delta 49), pack-reused 0 (from 0)
Receiving objects: 100% (472/472), 289.86 KiB | 7.07 MiB/s, done.
Resolving deltas: 100% (99/99), done.
$ bundle exec puppet-fixtures clean
```
