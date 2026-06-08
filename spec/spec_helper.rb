ENV["RAILS_ENV"] ||= "test"
ENV["SECRET_KEY_BASE"] ||= "a" * 64

require File.expand_path("../test/dummy/config/environment", __dir__)
require "rspec/rails"
require "factory_bot_rails"
require "bcrypt"

load File.expand_path("../test/dummy/db/schema.rb", __dir__)

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.include FactoryBot::Syntax::Methods

  # ThecoreAuthCommonsCanCanCanConcern (included via after_initialize) overrides
  # Ability#initialize to query Permission.joins(roles: :users). The permissions
  # tables exist but are empty in tests, so the query returns no abilities.
  # Re-override after all Rails initialization to grant :manage, :all.
  config.before(:suite) do
    Ability.define_method(:initialize) do |user|
      return unless user
      can :manage, :all
    end
  end
end
