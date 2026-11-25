require "rails_helper"

# GET /api/v2|v3/info/settings returns every setting except the value of a Secret setting, which
# is write-only (host ADR 0046 point 10, host Odoo #6084): the key stays, its value is null.
RSpec.describe "API info/settings", type: :request do
  let!(:user) { create(:user) }

  before do
    ThecoreSettings::Setting.create!(ns: "smtp", key: "password", raw: "Smtp-S3cret")
    ThecoreSettings::Setting.create!(ns: "smtp", key: "user_name", raw: "mailer")
    ThecoreSettings::Setting.create!(ns: "vapid", key: "private_key", raw: "PRIVATE-PEM")
    ThecoreSettings::Setting.create!(ns: "vapid", key: "public_key", raw: "PUBLIC-PEM")
  end

  %w[v2 v3].each do |version|
    it "#{version} keeps the secret keys with a null value and the other values as they are" do
      get "/api/#{version}/info/settings", headers: auth_headers_for(user)

      expect(response).to have_http_status(200)
      expect(response.body).not_to include("Smtp-S3cret", "PRIVATE-PEM")
      body = JSON.parse(response.body)
      expect(body["smtp"]).to eq("password" => nil, "user_name" => "mailer")
      expect(body["vapid"]).to eq("private_key" => nil, "public_key" => "PUBLIC-PEM")
    end
  end
end
