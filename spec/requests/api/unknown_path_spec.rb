require "rails_helper"

# A path that names no class at all reached the generic CRUD with a nil model and answered 500
# (NoMethodError on nil). It is a 404, like a path naming a class that isn't a model. Found while
# removing POST /api/v2|v3/auth/jwt (host Odoo #5860), which now falls through to the catchall.
RSpec.describe "API path naming no class", type: :request do
  let(:headers) { auth_headers_for(create(:user)).merge("Content-Type" => "application/json") }

  %w[v2 v3].each do |version|
    it "answers 404 in #{version} for POST and GET" do
      post "/api/#{version}/no_such_things", params: {}.to_json, headers: headers
      expect(response).to have_http_status(404)

      get "/api/#{version}/no_such_things", headers: headers
      expect(response).to have_http_status(404)

      get "/api/#{version}/no_such_things/custom_action/anything", headers: headers
      expect(response).to have_http_status(404)
    end
  end

  it "still lets the info endpoints that resolve no model through" do
    get "/api/v2/info/heartbeat", headers: headers

    expect(response).to have_http_status(200)
  end
end
