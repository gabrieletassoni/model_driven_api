require "rails_helper"

# Pins a deliberate, long-standing v2 contract (not a bug): an index returning no records
# answers 404 with an empty JSON array; `always_ok` (added in 22d54f3) opts out and answers
# 200. Clients branch on this, so changing the default is a breaking API change. v3 always
# answers 200 with {"data":[],"meta":{"total":0}}.
RSpec.describe "API v2 index on an empty collection", type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_headers_for(user) }

  before { Role.delete_all }

  it "answers 404 with an empty array by default" do
    get "/api/v2/roles", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(JSON.parse(response.body)).to eq([])
  end

  it "answers 200 with an empty array when always_ok is passed" do
    get "/api/v2/roles", params: { always_ok: true }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to eq([])
  end

  it "answers 200 when there are records" do
    create(:role)
    get "/api/v2/roles", headers: headers
    expect(response).to have_http_status(:ok)
  end
end
