require "rails_helper"

RSpec.describe "API v2 PushSubscriber custom actions", type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_headers_for(user) }

  before do
    ThecoreSettings::Setting.find_or_create_by!(ns: "vapid", key: "public_key") do |s|
      s.raw = "test_vapid_public_key_base64"
      s.kind = "string"
    end
  end

  describe "GET /api/v2/push_subscribers/custom_action/vapid_public_key" do
    it "returns HTTP 200 without authentication" do
      get "/api/v2/push_subscribers/custom_action/vapid_public_key"
      expect(response).to have_http_status(:ok)
    end

    it "returns the VAPID public key" do
      get "/api/v2/push_subscribers/custom_action/vapid_public_key"
      json = JSON.parse(response.body)
      expect(json["vapid_public_key"]).to eq("test_vapid_public_key_base64")
    end

    it "also works with authentication" do
      get "/api/v2/push_subscribers/custom_action/vapid_public_key", headers: headers
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /api/v3/push_subscribers/custom_action/vapid_public_key" do
    it "returns HTTP 200 without authentication" do
      get "/api/v3/push_subscribers/custom_action/vapid_public_key"
      expect(response).to have_http_status(:ok)
    end

    it "returns the VAPID public key" do
      get "/api/v3/push_subscribers/custom_action/vapid_public_key"
      json = JSON.parse(response.body)
      expect(json["vapid_public_key"]).to eq("test_vapid_public_key_base64")
    end
  end

  describe "POST /api/v2/push_subscribers/custom_action/subscribe" do
    let(:subscription_params) do
      {
        endpoint: "https://push.example.com/test-endpoint-#{SecureRandom.hex(8)}",
        p256dh: "test_p256dh_key",
        auth: "test_auth_secret",
        user_agent: "Mozilla/5.0 TestBrowser"
      }
    end

    it "returns HTTP 201 when creating a new subscription" do
      post "/api/v2/push_subscribers/custom_action/subscribe",
           params: subscription_params.to_json,
           headers: headers.merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:created)
    end

    it "creates a PushSubscriber record" do
      expect {
        post "/api/v2/push_subscribers/custom_action/subscribe",
             params: subscription_params.to_json,
             headers: headers.merge("Content-Type" => "application/json")
      }.to change(PushSubscriber, :count).by(1)
    end

    it "associates the subscriber with the current user" do
      post "/api/v2/push_subscribers/custom_action/subscribe",
           params: subscription_params.to_json,
           headers: headers.merge("Content-Type" => "application/json")
      subscriber = PushSubscriber.find_by(endpoint: subscription_params[:endpoint])
      expect(subscriber.user).to eq(user)
    end

    context "when subscribing again with the same endpoint" do
      before do
        PushSubscriber.subscribe_for(
          user,
          endpoint: subscription_params[:endpoint],
          p256dh: "old_key",
          auth: "old_auth",
          user_agent: "OldBrowser"
        )
      end

      it "returns HTTP 200 (update, not create)" do
        post "/api/v2/push_subscribers/custom_action/subscribe",
             params: subscription_params.to_json,
             headers: headers.merge("Content-Type" => "application/json")
        expect(response).to have_http_status(:ok)
      end

      it "does not create a new record" do
        expect {
          post "/api/v2/push_subscribers/custom_action/subscribe",
               params: subscription_params.to_json,
               headers: headers.merge("Content-Type" => "application/json")
        }.not_to change(PushSubscriber, :count)
      end

      it "updates p256dh and auth on the existing record" do
        post "/api/v2/push_subscribers/custom_action/subscribe",
             params: subscription_params.to_json,
             headers: headers.merge("Content-Type" => "application/json")
        subscriber = PushSubscriber.find_by(endpoint: subscription_params[:endpoint])
        expect(subscriber.p256dh).to eq("test_p256dh_key")
        expect(subscriber.auth).to eq("test_auth_secret")
      end
    end

    context "when re-subscribing on an expired subscriber" do
      before do
        sub = PushSubscriber.subscribe_for(
          user,
          endpoint: subscription_params[:endpoint],
          p256dh: "old_key",
          auth: "old_auth"
        )
        sub.expire!
      end

      it "returns HTTP 200" do
        post "/api/v2/push_subscribers/custom_action/subscribe",
             params: subscription_params.to_json,
             headers: headers.merge("Content-Type" => "application/json")
        expect(response).to have_http_status(:ok)
      end

      it "resets expired_at to nil" do
        post "/api/v2/push_subscribers/custom_action/subscribe",
             params: subscription_params.to_json,
             headers: headers.merge("Content-Type" => "application/json")
        subscriber = PushSubscriber.find_by(endpoint: subscription_params[:endpoint])
        expect(subscriber.expired_at).to be_nil
      end
    end

    it "returns 401 without authentication" do
      post "/api/v2/push_subscribers/custom_action/subscribe",
           params: subscription_params.to_json,
           headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end

    context "when user is non-admin (no PushSubscriber CanCan permission)" do
      around do |example|
        # Temporarily remove the spec-wide `can :manage, :all` patch so the
        # controller's CanCan check reflects real production abilities.
        original_initialize = Ability.instance_method(:initialize)
        Ability.define_method(:initialize) { |_user| nil }
        example.run
        Ability.define_method(:initialize, original_initialize)
      end

      it "returns 201 (subscribe must succeed regardless of CanCan model permissions)" do
        post "/api/v2/push_subscribers/custom_action/subscribe",
             params: subscription_params.to_json,
             headers: headers.merge("Content-Type" => "application/json")
        expect(response).to have_http_status(:created)
      end
    end
  end

  describe "POST /api/v2/push_subscribers/custom_action/send_push (single)" do
    let(:subscriber) { create(:push_subscriber, user: user) }

    before do
      allow(ThecoreBackendCommons::PushNotificationService).to receive(:dispatch) do |_sub, message|
        message
      end
    end

    it "returns 201 when subscriber is active and params are valid" do
      post "/api/v2/push_subscribers/custom_action/send_push",
           params: { push_subscriber_id: subscriber.id, title: "Hello", body: "World" }.to_json,
           headers: headers.merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:created)
    end

    it "creates a PushMessage record" do
      expect {
        post "/api/v2/push_subscribers/custom_action/send_push",
             params: { push_subscriber_id: subscriber.id, title: "Hello", body: "World" }.to_json,
             headers: headers.merge("Content-Type" => "application/json")
      }.to change(PushMessage, :count).by(1)
    end

    it "returns 404 when subscriber is not found" do
      post "/api/v2/push_subscribers/custom_action/send_push",
           params: { push_subscriber_id: 0, title: "Hello", body: "World" }.to_json,
           headers: headers.merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:not_found)
    end

    it "returns 422 when title is missing" do
      post "/api/v2/push_subscribers/custom_action/send_push",
           params: { push_subscriber_id: subscriber.id, body: "World" }.to_json,
           headers: headers.merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "POST /api/v2/push_subscribers/custom_action/send_push (bulk)" do
    let(:subscriber1) { create(:push_subscriber, user: user) }
    let(:subscriber2) { create(:push_subscriber, user: user) }

    before do
      allow(PushDispatchJob).to receive(:perform_later)
    end

    it "returns 201 with created and failed arrays" do
      post "/api/v2/push_subscribers/custom_action/send_push",
           params: { push_subscriber_ids: [subscriber1.id, subscriber2.id, 0], title: "Bulk", body: "Message" }.to_json,
           headers: headers.merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["created"].length).to eq(2)
      expect(json["failed"]).to eq([0])
    end

    it "creates a PushMessage for each valid subscriber" do
      expect {
        post "/api/v2/push_subscribers/custom_action/send_push",
             params: { push_subscriber_ids: [subscriber1.id, subscriber2.id], title: "Bulk", body: "Message" }.to_json,
             headers: headers.merge("Content-Type" => "application/json")
      }.to change(PushMessage, :count).by(2)
    end

    it "enqueues a PushDispatchJob for each valid subscriber" do
      post "/api/v2/push_subscribers/custom_action/send_push",
           params: { push_subscriber_ids: [subscriber1.id, subscriber2.id], title: "Bulk", body: "Message" }.to_json,
           headers: headers.merge("Content-Type" => "application/json")
      expect(PushDispatchJob).to have_received(:perform_later).exactly(2).times
    end

    it "returns empty created and all ids in failed when no subscribers are active" do
      post "/api/v2/push_subscribers/custom_action/send_push",
           params: { push_subscriber_ids: [0, 99999], title: "Bulk", body: "Message" }.to_json,
           headers: headers.merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["created"]).to be_empty
      expect(json["failed"]).to match_array([0, 99999])
    end

    it "returns 422 when title is missing" do
      post "/api/v2/push_subscribers/custom_action/send_push",
           params: { push_subscriber_ids: [subscriber1.id], body: "Message" }.to_json,
           headers: headers.merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 422 when body is missing" do
      post "/api/v2/push_subscribers/custom_action/send_push",
           params: { push_subscriber_ids: [subscriber1.id], title: "Bulk" }.to_json,
           headers: headers.merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "POST /api/v2/push_subscribers/custom_action/broadcast_push" do
    let(:subscriber1) { create(:push_subscriber, user: user) }
    let(:subscriber2) { create(:push_subscriber, user: user) }

    before do
      subscriber1
      subscriber2
      allow(PushDispatchJob).to receive(:perform_later)
    end

    it "returns 201 with enqueued count" do
      post "/api/v2/push_subscribers/custom_action/broadcast_push",
           params: { title: "Broadcast", body: "Message" }.to_json,
           headers: headers.merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["enqueued"]).to eq(2)
    end

    it "creates a PushMessage for each active subscriber" do
      expect {
        post "/api/v2/push_subscribers/custom_action/broadcast_push",
             params: { title: "Broadcast", body: "Message" }.to_json,
             headers: headers.merge("Content-Type" => "application/json")
      }.to change(PushMessage, :count).by(2)
    end

    it "enqueues a PushDispatchJob for each active subscriber" do
      post "/api/v2/push_subscribers/custom_action/broadcast_push",
           params: { title: "Broadcast", body: "Message" }.to_json,
           headers: headers.merge("Content-Type" => "application/json")
      expect(PushDispatchJob).to have_received(:perform_later).exactly(2).times
    end

    it "returns enqueued: 0 when no active subscribers exist" do
      subscriber1.expire!
      subscriber2.expire!
      post "/api/v2/push_subscribers/custom_action/broadcast_push",
           params: { title: "Broadcast", body: "Message" }.to_json,
           headers: headers.merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["enqueued"]).to eq(0)
    end

    it "skips expired subscribers" do
      subscriber1.expire!
      post "/api/v2/push_subscribers/custom_action/broadcast_push",
           params: { title: "Broadcast", body: "Message" }.to_json,
           headers: headers.merge("Content-Type" => "application/json")
      json = JSON.parse(response.body)
      expect(json["enqueued"]).to eq(1)
    end

    it "returns 422 when title is missing" do
      post "/api/v2/push_subscribers/custom_action/broadcast_push",
           params: { body: "Message" }.to_json,
           headers: headers.merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 422 when body is missing" do
      post "/api/v2/push_subscribers/custom_action/broadcast_push",
           params: { title: "Broadcast" }.to_json,
           headers: headers.merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "POST /api/v2/push_subscribers/custom_action/acknowledge" do
    let(:subscriber) { create(:push_subscriber, user: user) }
    let(:message) { create(:push_message, push_subscriber: subscriber) }

    it "sets received_at when received: true is passed" do
      post "/api/v2/push_subscribers/custom_action/acknowledge",
           params: { push_message_id: message.id, received: true }.to_json,
           headers: headers.merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:ok)
      expect(message.reload.received_at).not_to be_nil
    end

    it "sets read_at when read: true is passed" do
      post "/api/v2/push_subscribers/custom_action/acknowledge",
           params: { push_message_id: message.id, read: true }.to_json,
           headers: headers.merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:ok)
      expect(message.reload.read_at).not_to be_nil
    end

    it "returns 404 when message is not found" do
      post "/api/v2/push_subscribers/custom_action/acknowledge",
           params: { push_message_id: 0, received: true }.to_json,
           headers: headers.merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:not_found)
    end

    it "returns a serializable body using PushMessage json_attrs, not PushSubscriber's" do
      post "/api/v2/push_subscribers/custom_action/acknowledge",
           params: { push_message_id: message.id, received: true, read: true }.to_json,
           headers: headers.merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json).to have_key("title")
      expect(json).not_to have_key("user")
    end
  end
end
