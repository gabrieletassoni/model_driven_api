FactoryBot.define do
  factory :push_message do
    association :push_subscriber
    sender { nil }
    title { "Test notification" }
    body { "Test body" }
    message_type { "communication" }
    url { nil }
    icon { nil }
    sent_at { nil }
    received_at { nil }
    read_at { nil }
  end
end
