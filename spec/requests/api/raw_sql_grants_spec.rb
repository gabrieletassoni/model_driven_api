require "rails_helper"

# The thecore_raw database role is what hides secrets from POST /api/v2|v3/raw/sql (host ADR 0048,
# Odoo #6093): the parser cannot see SQL hidden in strings, privileges can. Not transactional: the
# executor owns its transaction, and the grants are what a deploy leaves in the database.
RSpec.describe "API raw SQL under the thecore_raw role", type: :request do
  self.use_transactional_tests = false

  let!(:user) { create(:user) }
  let(:conn) { ActiveRecord::Base.connection }

  before { RawSqlGrants.apply! }

  after { user.destroy }

  def raw_sql(version, query)
    post "/api/#{version}/raw/sql", params: {query: query}.to_json,
      headers: auth_headers_for(user).merge("Content-Type" => "application/json")
  end

  def body = JSON.parse(response.body)

  {
    "users.encrypted_password" => "SELECT json_agg(encrypted_password) AS result FROM users",
    "a whole users row" => "SELECT json_agg(u) AS result FROM users u",
    "thecore_settings" => "SELECT json_agg(id) AS result FROM thecore_settings",
    "ldap_servers" => "SELECT json_agg(id) AS result FROM ldap_servers",
    "used_tokens" => "SELECT json_agg(id) AS result FROM used_tokens",
    "users through query_to_xml" => "SELECT query_to_xml('SELECT encrypted_password FROM users', true, false, '') AS result",
    "set_config('role') hidden in a string" => "SELECT query_to_xml('SELECT set_config(''role'', ''none'', true)', true, false, '') AS result",
    "set_config('session_authorization') hidden in a string" => "SELECT query_to_xml('SELECT set_config(''session_authorization'', ''postgres'', true)', true, false, '') AS result"
  }.each do |label, query|
    it "refuses #{label}: 422 in v3, 400 in v2, without PostgreSQL's message" do
      raw_sql("v3", query)
      expect(response).to have_http_status(422)
      expect(body).to eq("error" => "raw_sql_rejected", "reason" => "not_permitted")

      raw_sql("v2", query)
      expect(response).to have_http_status(400)
      expect(body).to eq("error" => "raw_sql_rejected", "reason" => "not_permitted")
    end
  end

  describe "GET info/raw_sql" do
    def info(version)
      get "/api/#{version}/info/raw_sql", headers: auth_headers_for(user)
    end

    it "reports full protection once the grants are applied" do
      %w[v2 v3].each do |version|
        info(version)
        expect(response).to have_http_status(200)
        expect(body).to eq("protection" => "full", "reasons" => [], "enforce" => true)
      end
    end

    it "reports reduced protection when the role could undo itself through set_config" do
      conn.execute("GRANT EXECUTE ON FUNCTION pg_catalog.set_config(text, text, boolean) TO PUBLIC")

      info("v2")

      expect(response).to have_http_status(200)
      expect(body).to eq("protection" => "reduced", "reasons" => ["set_config_executable"], "enforce" => true)
    ensure
      conn.execute("REVOKE EXECUTE ON FUNCTION pg_catalog.set_config(text, text, boolean) FROM PUBLIC")
    end

    it "is documented in the v2 and v3 OpenAPI specs" do
      %w[v2 v3].each do |version|
        get "/api/#{version}/info/openapi"
        expect(body["paths"]["/info/raw_sql"]["get"]["security"]).to eq([{"bearerAuth" => []}])
      end
    end

    it "requires authentication" do
      get "/api/v2/info/raw_sql"

      expect(response).to have_http_status(401)
    end
  end

  it "still answers a SELECT of the users' non-secret columns" do
    raw_sql("v3", "SELECT json_agg(email) AS result FROM users WHERE id = #{user.id}")

    expect(response).to have_http_status(200)
    expect(JSON.parse(body.first["result"])).to eq([user.email])
  end
end
