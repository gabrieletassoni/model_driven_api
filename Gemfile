source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

# Declare your gem's dependencies in model_driven_api.gemspec.
# Bundler will treat runtime dependencies like base dependencies, and
# development dependencies will be added by default to the :development group.
gemspec

# The Rails line this suite runs on (Odoo #6089, ADR 0033): Rails 8.1, the only one CI tests.
# Dual support is best effort: the gemspec names no Rails version, its dependencies must keep
# resolving on 7.2 too. `RAILS_VERSION=7.2 bundle update railties actionmailer && RAILS_VERSION=7.2 <run the suite>`
# runs it on 7.2.4 locally. Both lines are pinned because a fresh CI resolution otherwise drifts
# (Odoo #6088); minitest stays on 5, since Rails 7.2's test runner breaks on minitest 6.
RAILS_LINE = ENV["RAILS_VERSION"] == "7.2" ? ["~> 7.2.4"] : ["~> 8.1", ">= 8.1.4.1"]
gem "railties", *RAILS_LINE # pins the whole Rails line without adding frameworks the dummy app lacks
gem "minitest", "~> 5.25"

# Declare any dependencies that are still in development here instead of in
# your gemspec. These might include edge Rails or gems from your path or
# Git. Remember to move these dependencies to your gemspec before releasing
# your gem to rubygems.org.

# To use a debugger
# gem 'byebug', group: [:development, :test]

gem "thecore_settings", "~> 3.0"
gem "thecore_auth_commons", "~> 3.0"
# https://github.com/nebulab/simple_command
gem "simple_command", "~> 1.0"

# https://github.com/activerecord-hackery/ransack
gem 'ransack', "~> 4.1"
  
# https://github.com/cyu/rack-cors
gem 'rack-cors', "~> 2.0"

# Intelligent Merging (recursive and recognizes types)
# https://github.com/danielsdeleo/deep_merge
gem "deep_merge", '~> 1.2'
gem 'pg', '~> 1.1'

# JSON:API serialization (v3)
gem 'jsonapi-serializer', '~> 2.2'

# Pagination (v3)
gem 'pagy', '~> 9.0'

group :test do
  gem 'rspec-rails', '~> 7.0'
  gem 'factory_bot_rails', '~> 6.4'
  # JUnit XML report in CI: rspec --format RspecJunitFormatter --out <file>
  gem 'rspec_junit_formatter', '~> 0.6'
  gem 'actionmailer', *RAILS_LINE
end
