require "rails_helper"

# A secret column a model already hides (Devise's encrypted_password, a column in its own
# json_attrs[:except], write_only_attributes) is never readable through the API: not in v3
# attributes, not through v2 request options, not through Ransack filters or sorts (host Odoo #6313).
RSpec.describe "API-hidden secrets", type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_headers_for(user) }

  def body = JSON.parse(response.body)

  it "v3 never returns encrypted_password" do
    get "/api/v3/users/#{user.id}", headers: headers

    expect(response).to have_http_status(:ok)
    expect(body.dig("data", "attributes")).to include("email")
    expect(body.dig("data", "attributes")).not_to have_key("encrypted_password")
  end

  describe "Ransack" do
    let!(:other) { create(:user) }

    it "v2 q[] cannot filter by encrypted_password" do
      get "/api/v2/users", params: {a: {only: %w[id]}, q: {encrypted_password_start: other.encrypted_password}},
        headers: headers

      expect(body.map { |u| u["id"] }).to contain_exactly(user.id, other.id)
    end

    it "v2 q[s] cannot sort by encrypted_password" do
      user.update_column(:encrypted_password, "$2a$12$zzzz")
      other.update_column(:encrypted_password, "$2a$12$aaaa")
      ids = ->(sort) { get("/api/v2/users", params: {a: {only: %w[id]}, q: {s: sort}}, headers: headers) && body.map { |u| u["id"] } }

      expect(ids.call("encrypted_password asc")).to eq(ids.call("encrypted_password desc"))
    end

    it "v3 filter cannot match encrypted_password" do
      get "/api/v3/users", params: {filter: {encrypted_password: other.encrypted_password}}, headers: headers

      expect(body["data"].map { |u| u["id"].to_i }).to contain_exactly(user.id, other.id)
    end

    it "v3 sort cannot order by encrypted_password" do
      user.update_column(:encrypted_password, "$2a$12$zzzz")
      other.update_column(:encrypted_password, "$2a$12$aaaa")

      get "/api/v3/users", headers: headers
      unsorted = body["data"].map { |u| u["id"] }
      get "/api/v3/users", params: {sort: "-encrypted_password"}, headers: headers
      descending = body["data"].map { |u| u["id"] }
      get "/api/v3/users", params: {sort: "encrypted_password"}, headers: headers

      expect([descending, body["data"].map { |u| u["id"] }]).to eq([unsorted, unsorted])
    end

    it "keeps every other column filterable" do
      get "/api/v2/users", params: {a: {only: %w[id]}, q: {email_eq: other.email}}, headers: headers

      expect(body.map { |u| u["id"] }).to eq([other.id])
    end
  end
end
