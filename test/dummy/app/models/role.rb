class Role < ApplicationRecord
  include ModelDrivenApiRole

  has_many :role_users
  has_many :users, through: :role_users
end
