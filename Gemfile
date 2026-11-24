source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

# Declare your gem's dependencies in model_driven_api.gemspec.
# Bundler will treat runtime dependencies like base dependencies, and
# development dependencies will be added by default to the :development group.
gemspec

# The Rails line this suite is tested on, the host apps' one (Odoo #6088): Rails 7.2.4, which
# runs on json 3 (the old `json < 3.0` pin held Rails back at 7.2.3.x), and minitest 5 (Rails 7.2's
# test runner breaks on minitest 6). Without these pins a fresh CI resolution drifts: one run
# picked Rails 8.1, others Rails 7.2.3 with minitest 6. Odoo #6089 turns this into a 7.2/8.1 matrix.
gem "railties", "~> 7.2.4" # pins the whole Rails line without adding frameworks the dummy app lacks
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
  gem 'actionmailer', '~> 7.2'
end
