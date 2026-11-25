require "rails_helper"

# The OAuth routes exist only when a provider is configured (ThecoreAuthCommons.oauth_vars?), so
# the routes are redrawn here as on such an installation. POST /api/v2|v3/auth/jwt (the frontend
# token exchange) is gone (host Odoo #5860): no frontend used it. The OmniAuth callback stays.
RSpec.describe "API OAuth routes with a provider configured", type: :request do
  before do
    allow(ThecoreAuthCommons).to receive(:oauth_vars?).and_return(true)
    Rails.application.reload_routes!
  end

  after do
    RSpec::Mocks.space.proxy_for(ThecoreAuthCommons).reset
    Rails.application.reload_routes!
  end

  def route_for(method, path)
    Rails.application.routes.recognize_path(path, method: method)
  rescue ActionController::RoutingError
    nil
  end

  %w[v2 v3].each do |version|
    it "has no token exchange at POST /api/#{version}/auth/jwt: 404" do
      expect(route_for(:post, "/api/#{version}/auth/jwt")).not_to include(action: "exchange_token")
      expect(Api::V2::Auth::OauthController.action_methods).not_to include("exchange_token")

      post "/api/#{version}/auth/jwt", params: {provider: "google", provider_token: "x"}.to_json,
        headers: auth_headers_for(create(:user)).merge("Content-Type" => "application/json")
      expect(response).to have_http_status(404)
    end
  end

  it "keeps the OmniAuth callback" do
    expect(route_for(:get, "/auth/google/callback")).to include(controller: "api/v2/auth/oauth", action: "callback")
    expect(route_for(:get, "/api/v2/auth/google/callback")).to include(controller: "api/v2/auth/oauth", action: "callback")
  end
end
