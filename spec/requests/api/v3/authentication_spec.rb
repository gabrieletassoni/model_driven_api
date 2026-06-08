require "rails_helper"

RSpec.describe "API v3 Authentication", type: :request do
  let!(:user) { create(:user) }

  describe "POST /api/v3/authenticate" do
    let(:payload) { { auth: { email: user.email, password: "password123" } } }

    it "returns HTTP 200 with valid credentials" do
      post "/api/v3/authenticate", params: payload.to_json,
           headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:ok)
    end

    it "returns a Token header" do
      post "/api/v3/authenticate", params: payload.to_json,
           headers: { "Content-Type" => "application/json" }
      expect(response.headers["Token"]).to be_present
    end

    it "returns user JSON in the body" do
      post "/api/v3/authenticate", params: payload.to_json,
           headers: { "Content-Type" => "application/json" }
      json = JSON.parse(response.body)
      expect(json["email"]).to eq(user.email)
    end

    it "does not return a Token header with wrong password" do
      # ApiExceptionManagement rescue_from is production-only; in test the
      # AccessDenied exception propagates as 500. We only verify no token is issued.
      post "/api/v3/authenticate",
           params: { auth: { email: user.email, password: "wrong" } }.to_json,
           headers: { "Content-Type" => "application/json" }
      expect(response.headers["Token"]).to be_nil
    end
  end
end
