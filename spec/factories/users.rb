FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    encrypted_password { BCrypt::Password.create("password123") }
  end
end
