require "rails_helper"

RSpec.describe "API v3 Info", type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_headers_for(user) }

  describe "GET /api/v3/info/version" do
    it "returns HTTP 200 without authentication" do
      get "/api/v3/info/version"
      expect(response).to have_http_status(:ok)
    end

    it "returns a version key" do
      get "/api/v3/info/version"
      json = JSON.parse(response.body)
      expect(json).to have_key("version")
    end
  end

  describe "GET /api/v3/info/heartbeat" do
    it "returns HTTP 200 with valid token" do
      get "/api/v3/info/heartbeat", headers: headers
      expect(response).to have_http_status(:ok)
    end

    it "returns 401 without token" do
      get "/api/v3/info/heartbeat"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v3/info/roles" do
    it "returns HTTP 200 with valid token" do
      get "/api/v3/info/roles", headers: headers
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /api/v3/info/swagger" do
    it "returns HTTP 200 without authentication" do
      get "/api/v3/info/swagger"
      expect(response).to have_http_status(:ok)
    end

    it "returns a valid OpenAPI 3.0 object" do
      get "/api/v3/info/swagger"
      json = JSON.parse(response.body)
      expect(json["openapi"]).to eq("3.0.0")
    end

    it "sets server URL to /api/v3" do
      get "/api/v3/info/swagger"
      json = JSON.parse(response.body)
      expect(json["servers"].first["url"]).to end_with("/api/v3")
    end

    it "sets info.version to v3" do
      get "/api/v3/info/swagger"
      json = JSON.parse(response.body)
      expect(json["info"]["version"]).to eq("v3")
    end

    it "documents the authenticate path" do
      get "/api/v3/info/swagger"
      json = JSON.parse(response.body)
      expect(json["paths"]).to have_key("/authenticate")
    end

    it "documents role index with JSON:API collection schema" do
      create(:role)
      get "/api/v3/info/swagger"
      json = JSON.parse(response.body)
      role_index = json["paths"]["/roles"]["get"]
      expect(role_index).to be_present
      schema = role_index["responses"]["200"]["content"]["application/vnd.api+json"]["schema"]
      expect(schema["properties"]["data"]["type"]).to eq("array")
      expect(schema["properties"]["meta"]["properties"]["total"]["type"]).to eq("integer")
    end

    it "documents role show with JSON:API single resource schema" do
      get "/api/v3/info/swagger"
      json = JSON.parse(response.body)
      role_show = json["paths"]["/roles/{id}"]["get"]
      expect(role_show).to be_present
      schema = role_show["responses"]["200"]["content"]["application/vnd.api+json"]["schema"]
      expect(schema["properties"]["data"]["properties"]["id"]["type"]).to eq("string")
      expect(schema["properties"]["data"]["properties"]["type"]["type"]).to eq("string")
    end

    it "documents role destroy as 204 No Content" do
      get "/api/v3/info/swagger"
      json = JSON.parse(response.body)
      role_delete = json["paths"]["/roles/{id}"]["delete"]
      expect(role_delete["responses"]).to have_key("204")
    end

    it "documents filter[field] query parameters on index" do
      get "/api/v3/info/swagger"
      json = JSON.parse(response.body)
      params = json["paths"]["/roles"]["get"]["parameters"].map { |p| p["name"] }
      expect(params).to include("filter[name]")
    end

    it "documents page[number] and page[size] on index" do
      get "/api/v3/info/swagger"
      json = JSON.parse(response.body)
      params = json["paths"]["/roles"]["get"]["parameters"].map { |p| p["name"] }
      expect(params).to include("page[number]", "page[size]")
    end

    it "does not document a /roles/search path" do
      get "/api/v3/info/swagger"
      json = JSON.parse(response.body)
      expect(json["paths"].keys).not_to include("/roles/search")
    end

    it "does not document PUT on role" do
      get "/api/v3/info/swagger"
      json = JSON.parse(response.body)
      expect(json["paths"]["/roles/{id}"].keys).not_to include("put")
    end
  end

  describe "GET /api/v3/info/openapi" do
    it "returns the same spec as /swagger" do
      get "/api/v3/info/openapi"
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["info"]["version"]).to eq("v3")
    end
  end
end
