class Ability
  include CanCan::Ability

  def initialize(user)
    return unless user
    can :manage, :all
  end
end
