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
```

To install fixtures, run:

```console
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

## Environment Variables

`puppet_fixtures` will parse environment variables and replace them in the `.fixtures.yml` file at runtime.
This may leak sensitive information in logs, so be careful.
But this is particularly useful for CI systems where you want to use private repositories.

For example, given the following `.fixtures.yml`:

```yaml
fixtures:
  repositories:
    stdlib: https://github.com/puppetlabs/puppetlabs-stdlib
    mysql: https://ci-bot:${CI_JOB_TOKEN}@github.com/${CI_USER}/puppetlabs-mysql
```

Will replace `${CI_JOB_TOKEN}` and `${CI_USER}` with the values from the environment.
But only when those variables are set.

```console
$ export CI_USER=foobar
$ export CI_TOKEN=token.MC.T0ken_face
$ bundle exec puppet-fixtures show
Parsing .fixtures.yml

# ...

Repositories
  stdlib => git+https://github.com/puppetlabs/puppetlabs-stdlib
  mysql => git+https://ci-bot:token.MC.T0ken_face@github.com/foobar/puppetlabs-mysql
```

If you run this in GitLab CI, gitlab will mask the token in the logs.
Because it is a default variable, you don't need to set it yourself.
`CI_USER` is a custom variable, so you need to set it in your project/group settings.
Or it will remain as `${CI_USER}`.

```console
$ bundle exec puppet-fixtures show
# ...
Parsing .fixtures.yml
Repositories
  stdlib => git+https://github.com/puppetlabs/puppetlabs-stdlib
  mysql => git+https://ci-bot:[MASKED]@github.com/${CI_USER}/puppetlabs-mysql
```
