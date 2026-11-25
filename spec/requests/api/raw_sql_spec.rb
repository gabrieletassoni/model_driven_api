require "rails_helper"

# POST /api/v2|v3/raw/sql runs a query sent by any authenticated user (host ADR 0048, Odoo #5835):
# one plain SELECT, in a READ ONLY transaction with limits, always rolled back, never with
# PostgreSQL's error message in the answer. Not transactional: the executor opens its own
# top-level transaction, exactly as in production.
RSpec.describe "API raw SQL", type: :request do
  self.use_transactional_tests = false

  let!(:user) { create(:user) }
  let(:conn) { ActiveRecord::Base.connection }

  after do
    conn.execute("SELECT pg_advisory_unlock_all()")
    conn.execute("DELETE FROM roles WHERE name LIKE 'raw-sql-%'")
    conn.execute("DROP TABLE IF EXISTS raw_sql_copy")
    user.destroy
  end

  def raw_sql(version, query)
    post "/api/#{version}/raw/sql", params: { query: query }.to_json,
      headers: auth_headers_for(user).merge("Content-Type" => "application/json")
  end

  def body = JSON.parse(response.body)

  def with_env(vars)
    saved = vars.keys.to_h { |k| [k, ENV[k]] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    saved.each { |k, v| ENV[k] = v }
  end

  def create_roles(*names)
    names.each { |name| conn.execute("INSERT INTO roles (name, created_at, updated_at) VALUES (#{conn.quote(name)}, now(), now())") }
  end

  def role_names = conn.select_values("SELECT name FROM roles WHERE name LIKE 'raw-sql-%' ORDER BY name")

  describe "a statement that writes or keeps state" do
    {
      "several statements" => ["SELECT 1 AS result; INSERT INTO roles (name, created_at, updated_at) VALUES ('raw-sql-multi', now(), now())", "only_single_select"],
      "a data-modifying CTE" => ["WITH x AS (INSERT INTO roles (name, created_at, updated_at) VALUES ('raw-sql-cte', now(), now()) RETURNING id) SELECT json_agg(x) AS result FROM x", "data_modifying_statement"],
      "a CTE with UPDATE" => ["WITH x AS (UPDATE roles SET name = 'raw-sql-renamed' RETURNING id) SELECT json_agg(x) AS result FROM x", "data_modifying_statement"],
      "SELECT INTO" => ["SELECT name INTO raw_sql_copy FROM roles", "data_modifying_statement"],
      "FOR UPDATE" => ["SELECT json_agg(id) AS result FROM roles FOR UPDATE", "locking_clause"],
      "lo_create" => ["SELECT lo_create(0) AS result", "function_not_allowed"],
      "a session advisory lock" => ["SELECT pg_advisory_lock(4242) AS result", "function_not_allowed"],
      "set_config('role')" => ["SELECT set_config('role', 'none', true) AS result", "function_not_allowed"],
      "set_config('session_authorization')" => ["SELECT set_config('session_authorization', 'postgres', true) AS result", "function_not_allowed"],
      "a schema-qualified denied function" => ["SELECT pg_catalog.pg_terminate_backend(1) AS result", "function_not_allowed"],
      "EXPLAIN" => ["EXPLAIN SELECT 1", "only_single_select"],
      "a syntax error" => ["SELEC 1", "syntax_error"]
    }.each do |label, (query, reason)|
      it "rejects #{label} with 422 in v3 and 400 in v2, and writes nothing" do
        raw_sql("v3", query)
        expect(response).to have_http_status(422)
        expect(body).to eq("error" => "raw_sql_rejected", "reason" => reason)

        raw_sql("v2", query)
        expect(response).to have_http_status(400)
        expect(body).to eq("error" => "raw_sql_rejected", "reason" => reason)

        expect(role_names).to be_empty
        expect(conn.table_exists?("raw_sql_copy")).to be(false)
      end
    end
  end

  describe "a proper SELECT" do
    before { create_roles("raw-sql-a", "raw-sql-b") }

    let(:query) { "SELECT json_agg(name ORDER BY name) AS result FROM roles WHERE name LIKE 'raw-sql-%'" }

    it "answers in v2 with the value of result, as before" do
      raw_sql("v2", query)

      expect(response).to have_http_status(200)
      expect(response.body).to eq('["raw-sql-a", "raw-sql-b"]')
    end

    it "answers in v3 with the rows as a plain array, as before" do
      raw_sql("v3", query)

      expect(response).to have_http_status(200)
      expect(body).to eq([{"result" => '["raw-sql-a", "raw-sql-b"]'}])
    end
  end

  # query_to_xml runs SQL hidden in a string, out of the parser's sight (ADR 0048): the session
  # lock it takes must not outlive the request on the pooled connection.
  it "leaves no session advisory lock behind, even one taken out of the parser's sight" do
    raw_sql("v3", "SELECT query_to_xml('SELECT pg_advisory_lock(4242)', true, false, '') AS result")

    expect(response).to have_http_status(200)
    expect(conn.select_value("SELECT count(*) FROM pg_locks WHERE locktype = 'advisory' AND objid = 4242")).to eq(0)
  end

  it "runs the query READ ONLY, so a write the parser cannot see is not permitted" do
    raw_sql("v3", "SELECT nextval('roles_id_seq') AS result")

    expect(response).to have_http_status(422)
    expect(body).to eq("error" => "raw_sql_rejected", "reason" => "not_permitted")
  end

  it "stops a query over RAW_SQL_STATEMENT_TIMEOUT" do
    query = "SELECT count(*) AS result FROM generate_series(1, 1000000000)"
    with_env("RAW_SQL_STATEMENT_TIMEOUT" => "100ms") do
      raw_sql("v3", query)
      expect(response).to have_http_status(422)
      expect(body).to eq("error" => "raw_sql_failed", "reason" => "timeout")

      raw_sql("v2", query)
      expect(response).to have_http_status(400)
      expect(body).to eq("error" => "raw_sql_failed", "reason" => "timeout")
    end
  end

  it "answers 413 in v3 (400 in v2) for a result over RAW_SQL_MAX_RESULT_BYTES" do
    query = "SELECT repeat('x', 100) AS result"
    with_env("RAW_SQL_MAX_RESULT_BYTES" => "50") do
      raw_sql("v3", query)
      expect(response).to have_http_status(413)
      expect(body).to eq("error" => "raw_sql_failed", "reason" => "result_too_large")

      raw_sql("v2", query)
      expect(response).to have_http_status(400)
      expect(body).to eq("error" => "raw_sql_failed", "reason" => "result_too_large")
    end
  end

  it "rejects a query over RAW_SQL_MAX_QUERY_BYTES before parsing it" do
    with_env("RAW_SQL_MAX_QUERY_BYTES" => "20") do
      raw_sql("v3", "SELECT 1 AS result, 2 AS other, 3 AS third")
    end

    expect(response).to have_http_status(422)
    expect(body).to eq("error" => "raw_sql_rejected", "reason" => "query_too_large")
  end

  it "ignores a byte cap that is not a number instead of failing every query" do
    with_env("RAW_SQL_MAX_QUERY_BYTES" => "10MB") do
      raw_sql("v3", "SELECT 1 AS result")
    end

    expect(response).to have_http_status(200)
    expect(body).to eq([{"result" => 1}])
  end

  it "never answers with PostgreSQL's message, only the SQLSTATE" do
    raw_sql("v3", "SELECT secret_column AS result FROM roles")

    expect(response).to have_http_status(422)
    expect(body).to eq("error" => "raw_sql_failed", "reason" => "query_error", "sqlstate" => "42703")
    expect(response.body).not_to include("secret_column")
  end

  describe "with RAW_SQL_ENFORCE=false" do
    let(:logs) { [] }

    before do
      create_roles("raw-sql-a")
      entries = logs
      stub_const("IntegrationLog", Class.new { define_singleton_method(:create!) { |**attrs| entries << attrs } })
    end

    it "logs a rejected query as an IntegrationLog warning and runs it the old way" do
      with_env("RAW_SQL_ENFORCE" => "false") do
        raw_sql("v3", "SELECT name AS result FROM roles WHERE name = 'raw-sql-a' FOR UPDATE")
      end

      expect(response).to have_http_status(200)
      expect(body).to eq([{"result" => "raw-sql-a"}])
      expect(logs.size).to eq(1)
      expect(logs.first).to include(severity: "warning")
      expect(logs.first[:data]).to include(reason: "locking_clause")
    end

    it "falls back the old way in v2 too, answering with the value of result" do
      with_env("RAW_SQL_ENFORCE" => "false") do
        raw_sql("v2", "SELECT to_json(name) AS result FROM roles WHERE name = 'raw-sql-a' FOR UPDATE")
      end

      expect(response).to have_http_status(200)
      expect(response.body).to eq('"raw-sql-a"')
      expect(logs.size).to eq(1)
    end

    it "does not rerun a query that timed out" do
      with_env("RAW_SQL_ENFORCE" => "false", "RAW_SQL_STATEMENT_TIMEOUT" => "100ms") do
        raw_sql("v3", "SELECT count(*) AS result FROM generate_series(1, 1000000000)")
      end

      expect(response).to have_http_status(422)
      expect(body).to eq("error" => "raw_sql_failed", "reason" => "timeout")
      expect(logs).to be_empty
    end

    it "does not rerun a query that is simply broken" do
      with_env("RAW_SQL_ENFORCE" => "false") do
        raw_sql("v3", "SELECT secret_column AS result FROM roles")
      end

      expect(response).to have_http_status(422)
      expect(logs).to be_empty
    end
  end
end
