require "rails_helper"

# `a` is the short alias of `json_attrs`, the serialization options (only, except, methods,
# include) a caller may send in place of the model's own. Anything but a hash answers 400 naming
# the parameter, in every environment, instead of a 500 (host Odoo #6258).
RSpec.describe "API v2 json_attrs parameter", type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_headers_for(user) }

  before { create(:role, name: "Reader") }

  it "answers 400 naming the parameter when a is not a hash" do
    get "/api/v2/roles", params: { a: "1" }, headers: headers

    expect(response).to have_http_status(:bad_request)
    expect(JSON.parse(response.body)).to eq("error" => "The a parameter must be a hash, e.g. a[only][]=id")
  end

  it "answers 400 naming the parameter when json_attrs is not a hash" do
    get "/api/v2/roles", params: { json_attrs: "1" }, headers: headers

    expect(response).to have_http_status(:bad_request)
    expect(JSON.parse(response.body)).to eq("error" => "The json_attrs parameter must be a hash, e.g. json_attrs[only][]=id")
  end

  it "answers 400 when a is an array" do
    get "/api/v2/roles?a[]=id", headers: headers

    expect(response).to have_http_status(:bad_request)
  end

  it "answers 400 on the users endpoint" do
    get "/api/v2/users", params: { a: "1" }, headers: headers

    expect(response).to have_http_status(:bad_request)
  end

  it "leaves a plain destroy alone, which never reads a" do
    role = Role.find_by!(name: "Reader")
    delete "/api/v2/roles/#{role.id}?a=1", headers: headers

    expect(response).to have_http_status(:ok)
    expect(Role.exists?(role.id)).to be(false)
  end

  it "answers 400 on show too" do
    role = Role.find_by!(name: "Reader")
    get "/api/v2/roles/#{role.id}", params: { a: "1" }, headers: headers

    expect(response).to have_http_status(:bad_request)
  end

  it "creates nothing when a create carries a scalar a" do
    expect {
      post "/api/v2/roles?a=1", params: { role: { name: "Planner" } }.to_json, headers: headers
    }.not_to change(Role, :count)
    expect(response).to have_http_status(:bad_request)
  end

  it "changes nothing when an update carries a scalar a" do
    role = Role.find_by!(name: "Reader")
    put "/api/v2/roles/#{role.id}?a=1", params: { role: { name: "Writer" } }.to_json, headers: headers

    expect(response).to have_http_status(:bad_request)
    expect(role.reload.name).to eq("Reader")
  end

  it "serializes with a hash a as before" do
    get "/api/v2/roles?a[only][]=name", headers: headers

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to eq([{ "name" => "Reader" }])
  end

  it "serializes with a hash json_attrs as before" do
    get "/api/v2/roles?json_attrs[only][]=name", headers: headers

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to eq([{ "name" => "Reader" }])
  end

  it "ignores an empty a" do
    get "/api/v2/roles?a=", headers: headers

    expect(response).to have_http_status(:ok)
  end

  it "still ignores unknown parameters" do
    get "/api/v2/roles", params: { b: "1" }, headers: headers

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).map { |role| role["name"] }).to eq(["Reader"])
  end

  it "leaves v3 standard actions alone, which never read a" do
    get "/api/v3/roles", params: { a: "1" }, headers: headers

    expect(response).to have_http_status(:ok)
  end

  it "answers 400 on custom actions, v2 and v3, which serialize through json_attrs" do
    get "/api/v2/push_subscribers/custom_action/vapid_public_key", params: { a: "1" }
    expect(response).to have_http_status(:bad_request)

    get "/api/v3/push_subscribers/custom_action/vapid_public_key", params: { a: "1" }
    expect(response).to have_http_status(:bad_request)
  end
end
