source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

# Declare your gem's dependencies in model_driven_api.gemspec.
# Bundler will treat runtime dependencies like base dependencies, and
# development dependencies will be added by default to the :development group.
gemspec

# Declare any dependencies that are still in development here instead of in
# your gemspec. These might include edge Rails or gems from your path or
# Git. Remember to move these dependencies to your gemspec before releasing
# your gem to rubygems.org.

# To use a debugger
# gem 'byebug', group: [:development, :test]

gem "thecore_settings", "~> 3.0"
gem "thecore_auth_commons", "~> 3.0"
# TEMPORARY: thecore_backend_commons 3.5.0 (which contains DefaultModuleRegistry)
# was just published to RubyGems but its index hasn't propagated the new version
# yet (bundle install still resolves 3.4.1). Pin to the release/3 branch until
# `bundle update thecore_backend_commons` picks up 3.5.0 for real, then remove
# this override entirely -- the gemspec's own `~> 3.0` constraint needs no pin.
gem "thecore_backend_commons", "~> 3.0",
  git: "https://github.com/gabrieletassoni/thecore_backend_commons.git",
  branch: "release/3"
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
  gem 'actionmailer', '~> 7.2'
end
