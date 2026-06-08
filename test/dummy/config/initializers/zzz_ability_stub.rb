# Override Ability#initialize after thecore_auth_commons' after_initialize hook
# includes ThecoreAuthCommonsCanCanCanConcern. That concern adds a Permission.joins
# query requiring tables not present in the test schema. This runs last (zzz_) so
# our after_initialize callback is registered after thecore's and wins.
Rails.application.configure do
  config.after_initialize do
    Ability.define_method(:initialize) do |user|
      return unless user
      can :manage, :all
    end
  end
end
