FactoryBot.define do
  factory :push_subscriber do
    association :user
    sequence(:endpoint) { |n| "https://push.example.com/subscriber-#{n}" }
    p256dh { "test_p256dh_key" }
    auth { "test_auth_secret" }
    user_agent { "Mozilla/5.0 TestBrowser" }
    expired_at { nil }
  end
end
