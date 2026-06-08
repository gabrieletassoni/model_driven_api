require "rails_helper"

RSpec.describe "API v3 Roles", type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_headers_for(user) }

  describe "GET /api/v3/roles" do
    before { create_list(:role, 3) }

    it "returns HTTP 200" do
      get "/api/v3/roles", headers: headers
      expect(response).to have_http_status(:ok)
    end

    it "returns a JSON:API compliant envelope" do
      get "/api/v3/roles", headers: headers
      json = JSON.parse(response.body)
      expect(json).to have_key("data")
      expect(json["data"]).to be_an(Array)
    end

    it "returns resource objects with correct type" do
      get "/api/v3/roles", headers: headers
      json = JSON.parse(response.body)
      expect(json["data"].first["type"]).to eq("roles")
    end

    it "returns attributes from json_attrs" do
      get "/api/v3/roles", headers: headers
      json = JSON.parse(response.body)
      attrs = json["data"].first["attributes"]
      expect(attrs).to have_key("name")
    end

    it "returns all 3 records" do
      get "/api/v3/roles", headers: headers
      json = JSON.parse(response.body)
      expect(json["data"].length).to eq(3)
    end

    context "with pagination" do
      it "returns page[number] and page[size] subsets" do
        get "/api/v3/roles", params: { "page[number]" => 1, "page[size]" => 2 }, headers: headers
        json = JSON.parse(response.body)
        expect(json["data"].length).to eq(2)
        expect(json).to have_key("meta")
        expect(json["meta"]).to have_key("total")
      end
    end

    context "with filtering" do
      let!(:target) { create(:role, name: "Needle") }

      it "filters by field value" do
        get "/api/v3/roles", params: { "filter[name]" => "Needle" }, headers: headers
        json = JSON.parse(response.body)
        expect(json["data"].length).to eq(1)
        expect(json["data"].first["attributes"]["name"]).to eq("Needle")
      end
    end

    context "with sorting" do
      it "sorts ascending" do
        get "/api/v3/roles", params: { sort: "name" }, headers: headers
        json = JSON.parse(response.body)
        names = json["data"].map { |d| d["attributes"]["name"] }
        expect(names).to eq(names.sort)
      end

      it "sorts descending with - prefix" do
        get "/api/v3/roles", params: { sort: "-name" }, headers: headers
        json = JSON.parse(response.body)
        names = json["data"].map { |d| d["attributes"]["name"] }
        expect(names).to eq(names.sort.reverse)
      end
    end

    context "with sparse fieldsets" do
      it "returns only requested fields when fields[roles]=name" do
        get "/api/v3/roles", params: { "fields[roles]" => "name" }, headers: headers
        json = JSON.parse(response.body)
        attrs = json["data"].first["attributes"]
        expect(attrs).to have_key("name")
        expect(attrs.keys).to eq(["name"])
      end
    end
  end

  describe "GET /api/v3/roles/:id" do
    let!(:role) { create(:role, name: "Specific") }

    it "returns HTTP 200" do
      get "/api/v3/roles/#{role.id}", headers: headers
      expect(response).to have_http_status(:ok)
    end

    it "returns a single JSON:API resource object" do
      get "/api/v3/roles/#{role.id}", headers: headers
      json = JSON.parse(response.body)
      expect(json["data"]["type"]).to eq("roles")
      expect(json["data"]["id"]).to eq(role.id.to_s)
      expect(json["data"]["attributes"]["name"]).to eq("Specific")
    end

    context "with default sideloading from json_attrs[:include]" do
      let!(:member) { create(:user) }
      before { role.users << member }

      it "includes a relationships.users key by default" do
        get "/api/v3/roles/#{role.id}", headers: headers
        json = JSON.parse(response.body)
        expect(json["data"]["relationships"]).to have_key("users")
      end

      it "sideloads users in the included array by default" do
        get "/api/v3/roles/#{role.id}", headers: headers
        json = JSON.parse(response.body)
        expect(json).to have_key("included")
        included_types = json["included"].map { |r| r["type"] }
        expect(included_types).to include("users")
      end

      it "sideloaded users expose only id (per nested only: [:id] spec)" do
        get "/api/v3/roles/#{role.id}", headers: headers
        json = JSON.parse(response.body)
        included_user = json["included"].find { |r| r["type"] == "users" }
        expect(included_user["attributes"].to_h).to be_empty
        expect(included_user["id"]).to eq(member.id.to_s)
      end
    end

    context "with ?include= override" do
      let!(:member) { create(:user) }
      before { role.users << member }

      it "suppresses sideloading when ?include= is empty" do
        get "/api/v3/roles/#{role.id}", params: { include: "" }, headers: headers
        json = JSON.parse(response.body)
        expect(json).not_to have_key("included")
      end
    end
  end

  describe "POST /api/v3/roles" do
    let(:payload) do
      {
        data: {
          type: "roles",
          attributes: { name: "Created" }
        }
      }
    end

    it "returns HTTP 201" do
      post "/api/v3/roles", params: payload.to_json, headers: headers
      expect(response).to have_http_status(:created)
    end

    it "creates the record" do
      expect {
        post "/api/v3/roles", params: payload.to_json, headers: headers
      }.to change(Role, :count).by(1)
    end

    it "returns the created resource as JSON:API" do
      post "/api/v3/roles", params: payload.to_json, headers: headers
      json = JSON.parse(response.body)
      expect(json["data"]["type"]).to eq("roles")
      expect(json["data"]["attributes"]["name"]).to eq("Created")
    end
  end

  describe "PATCH /api/v3/roles/:id" do
    let!(:role) { create(:role, name: "Old") }
    let(:payload) do
      {
        data: {
          type: "roles",
          id: role.id.to_s,
          attributes: { name: "Updated" }
        }
      }
    end

    it "returns HTTP 200" do
      patch "/api/v3/roles/#{role.id}", params: payload.to_json, headers: headers
      expect(response).to have_http_status(:ok)
    end

    it "updates the record" do
      patch "/api/v3/roles/#{role.id}", params: payload.to_json, headers: headers
      expect(role.reload.name).to eq("Updated")
    end

    it "returns the updated resource as JSON:API" do
      patch "/api/v3/roles/#{role.id}", params: payload.to_json, headers: headers
      json = JSON.parse(response.body)
      expect(json["data"]["attributes"]["name"]).to eq("Updated")
    end
  end

  describe "DELETE /api/v3/roles/:id" do
    let!(:role) { create(:role) }

    it "returns HTTP 204" do
      delete "/api/v3/roles/#{role.id}", headers: headers
      expect(response).to have_http_status(:no_content)
    end

    it "destroys the record" do
      expect {
        delete "/api/v3/roles/#{role.id}", headers: headers
      }.to change(Role, :count).by(-1)
    end
  end

  describe "authentication" do
    it "returns 401 without a token" do
      get "/api/v3/roles"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 with an expired token" do
      expired_token = JsonWebToken.encode({ user_id: user.id }, 1.hour.ago.to_i)
      get "/api/v3/roles", headers: { "Authorization" => "Bearer #{expired_token}" }
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
