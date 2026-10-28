require "rails_helper"

# Rotating SECRET_KEY_BASE (Odoo #5836): for a short window after a rotation, a JWT signed with
# the previous key is still accepted, and the response renews it with the current key, so app
# users never have to log in again.
RSpec.describe "API v2 SECRET_KEY_BASE rotation", type: :request do
  let(:user) { create(:user) }
  let(:previous_key) { "p" * 64 }
  let(:token_from_previous_key) { JWT.encode({ user_id: user.id, exp: 30.minutes.from_now.to_i }, previous_key) }
  let(:headers) { { "Authorization" => "Bearer #{token_from_previous_key}", "Accept" => "application/json" } }

  around do |example|
    saved = ENV.to_h.slice("SECRET_KEY_BASE_PREVIOUS", "SECRET_KEY_BASE_PREVIOUS_EXPIRES_AT")
    example.run
  ensure
    ENV.delete("SECRET_KEY_BASE_PREVIOUS")
    ENV.delete("SECRET_KEY_BASE_PREVIOUS_EXPIRES_AT")
    ENV.update(saved)
  end

  context "while the previous key's window is open" do
    before do
      ENV["SECRET_KEY_BASE_PREVIOUS"] = previous_key
      ENV["SECRET_KEY_BASE_PREVIOUS_EXPIRES_AT"] = 1.hour.from_now.utc.iso8601
    end

    it "accepts a token signed with the previous key" do
      get "/api/v2/roles?always_ok=true", headers: headers
      expect(response).to have_http_status(:ok)
    end

    it "renews it with a token signed with the current key" do
      get "/api/v2/roles?always_ok=true", headers: headers
      renewed = response.headers["Token"]
      expect { JWT.decode(renewed, ENV["SECRET_KEY_BASE"]) }.not_to raise_error
    end
  end

  it "rejects a token signed with the previous key once its window has closed" do
    ENV["SECRET_KEY_BASE_PREVIOUS"] = previous_key
    ENV["SECRET_KEY_BASE_PREVIOUS_EXPIRES_AT"] = 1.minute.ago.utc.iso8601
    get "/api/v2/roles?always_ok=true", headers: headers
    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects a token signed with the previous key when no window end is set" do
    ENV["SECRET_KEY_BASE_PREVIOUS"] = previous_key
    get "/api/v2/roles?always_ok=true", headers: headers
    expect(response).to have_http_status(:unauthorized)
  end
end
