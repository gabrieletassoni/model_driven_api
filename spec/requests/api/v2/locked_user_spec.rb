require "rails_helper"

# A locked user (users.locked, set from RailsAdmin) is refused on every API channel: login with
# a password or through LDAP, every request with a JWT still valid from before the lock (which
# must not be renewed either), and the OAuth callback (Odoo #6051). Unlocked users change nothing.
RSpec.describe "API v2 locked user", type: :request do
  let(:password) { "password123" }
  let!(:user) { create(:user) }

  def lock(record) = record.update_columns(locked: true)

  def authenticate(password)
    post "/api/v2/authenticate", params: { auth: { email: user.email, password: password } }, as: :json
  end

  describe "POST /api/v2/authenticate" do
    it "gives an unlocked user a token" do
      authenticate(password)

      expect(response).to have_http_status(:ok)
      expect(response.headers["Token"]).to be_present
    end

    # The refusal must look like a wrong password: same status (401 in production, where
    # ApiExceptionManagement maps AccessDenied; the bare exception elsewhere), no token.
    def wrong_password_status
      authenticate("Wrong-Pass-123!")
      response.status
    end

    it "refuses a locked user with the right password, like a wrong password" do
      expected_status = wrong_password_status
      lock(user)

      authenticate(password)

      expect(response.status).to eq(expected_status).and(satisfy { |status| status != 200 })
      expect(response.headers["Token"]).to be_nil
    end

    it "refuses a locked user that LDAP authenticates, like a wrong password" do
      expected_status = wrong_password_status
      lock(user)
      allow(Ldap::Authenticator).to receive(:new).and_return(double(authenticate: user.reload))

      authenticate("the-ldap-password")

      expect(response.status).to eq(expected_status)
      expect(response.headers["Token"]).to be_nil
    end
  end

  describe "a request with a JWT issued before the lock" do
    let(:headers) { { "Authorization" => "Bearer #{JsonWebToken.encode(user_id: user.id)}", "Accept" => "application/json" } }

    it "is served, with a renewed token, while the user is unlocked" do
      get "/api/v2/roles?always_ok=true", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.headers["Token"]).to be_present
    end

    it "answers 401 without renewing the token once the user is locked" do
      lock(user)

      get "/api/v2/roles?always_ok=true", headers: headers

      expect(response).to have_http_status(:unauthorized)
      expect(response.headers["Token"]).to be_nil
    end
  end
end

# The OAuth routes exist only when a provider is configured, so the callback is routed here by hand,
# with request.env["omniauth.auth"] set as the OmniAuth middleware would.
RSpec.describe Api::V2::Auth::OauthController, type: :controller do
  routes do
    ActionDispatch::Routing::RouteSet.new.tap do |set|
      set.draw { get "auth/:provider/callback", to: "api/v2/auth/oauth#callback" }
    end
  end

  let!(:user) { create(:user) }

  def oauth_callback_for(email)
    request.env["omniauth.auth"] = OmniAuth::AuthHash.new(
      provider: "google", uid: "123", info: { email: email, first_name: "Work", last_name: "Er" }
    )
    get :callback, params: { provider: "google" }
  end

  it "gives an unlocked user a token" do
    oauth_callback_for(user.email)

    expect(response).to have_http_status(:ok)
    expect(response.headers["Token"]).to be_present
  end

  it "refuses a locked user" do
    user.update_columns(locked: true)

    oauth_callback_for(user.email)

    expect(response).to have_http_status(:unauthorized)
    expect(response.headers["Token"]).to be_nil
  end
end
