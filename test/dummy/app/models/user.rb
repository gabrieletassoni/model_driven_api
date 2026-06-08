class User < ApplicationRecord
  include ModelDrivenApiUser

  has_many :role_users
  has_many :roles, through: :role_users

  # Mirrors thecore_auth_commons User#authenticate (Devise database_authenticatable).
  # BCrypt check against encrypted_password — the column Devise uses.
  def authenticate(password)
    return nil if encrypted_password.blank?
    BCrypt::Password.new(encrypted_password).is_password?(password) ? self : nil
  end
end
