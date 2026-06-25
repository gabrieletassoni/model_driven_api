FactoryBot.define do
  factory :push_message do
    association :push_subscriber
    sender { nil }
    title { "Test notification" }
    body { "Test body" }
    url { nil }
    icon { nil }
    sent_at { nil }
    received_at { nil }
    read_at { nil }
  end
end
