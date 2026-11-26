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

  # Mirrors Devise::Models::Authenticatable#serializable_hash (the host's User is a Devise model):
  # Devise hides these columns by adding them to :except (or :force_except).
  DEVISE_BLACKLIST_FOR_SERIALIZATION = %i[
    encrypted_password reset_password_token reset_password_sent_at remember_created_at sign_in_count
    current_sign_in_at last_sign_in_at current_sign_in_ip last_sign_in_ip password_salt confirmation_token
    confirmed_at confirmation_sent_at remember_token unconfirmed_email failed_attempts unlock_token locked_at
  ].freeze

  def serializable_hash(options = nil)
    options = options.try(:dup) || {}
    options[:except] = Array(options[:except]).dup
    if options[:force_except]
      options[:except].concat Array(options[:force_except])
    else
      options[:except].concat DEVISE_BLACKLIST_FOR_SERIALIZATION
    end
    super(options)
  end

  # Mirrors thecore_auth_commons User#active_for_authentication? (>= 3.7.0, Devise's own is
  # true): a locked user may not authenticate.
  def active_for_authentication?
    !locked?
  end
end
