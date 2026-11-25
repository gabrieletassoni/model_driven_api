require "rails_helper"
require "rake"

# rake thecore:db:raw_grants (host ADR 0048, Odoo #6093): rebuilds the thecore_raw role's privileges
# at every deploy. Transactional: the role, the grants and the DDL below are rolled back.
RSpec.describe "rake thecore:db:raw_grants" do
  let(:conn) { ActiveRecord::Base.connection }

  before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?("thecore:db:raw_grants") }

  def raw_grants
    task = Rake::Task["thecore:db:raw_grants"]
    task.reenable
    task.invoke
  end

  def readable?(table, column)
    conn.select_value("SELECT has_column_privilege('thecore_raw', #{conn.quote(table)}, #{conn.quote(column)}, 'SELECT')")
  end

  it "leaves no column whose name looks like a secret readable by thecore_raw" do
    raw_grants

    columns = conn.select_rows(<<~SQL)
      SELECT c.relname, a.attname
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      JOIN pg_attribute a ON a.attrelid = c.oid
      WHERE n.nspname = current_schema() AND c.relkind IN ('r', 'p', 'v', 'm', 'f') AND a.attnum > 0 AND NOT a.attisdropped
    SQL
    secrets = columns.select { |_, column| column.match?(/passw|secret|token|_key|crypt|salt|certificate|otp|ssn|cvv|cvc/i) }

    expect(secrets).to include(["users", "encrypted_password"], ["ldap_servers", "admin_password"])
    expect(secrets.select { |table, column| readable?(table, column) }).to eq([])
  end

  it "denies every column of the excluded tables" do
    raw_grants

    %w[ldap_servers thecore_settings used_tokens push_subscribers].each do |table|
      expect(readable?(table, "id")).to be(false), "#{table}.id is readable"
    end
  end

  it "makes a new non-secret column on users readable, and a new secret one not, at the next run" do
    raw_grants
    conn.execute("ALTER TABLE users ADD COLUMN nickname varchar, ADD COLUMN api_key varchar")
    expect(readable?("users", "nickname")).to be(false)

    raw_grants

    expect(readable?("users", "nickname")).to be(true)
    expect(readable?("users", "email")).to be(true)
    expect(readable?("users", "api_key")).to be(false)
  end

  it "keeps a table created after the run readable" do
    raw_grants
    conn.execute("CREATE TABLE raw_grants_new_things (id bigint, name varchar)")

    expect(readable?("raw_grants_new_things", "name")).to be(true)
  end

  # A view reads with its owner's privileges (the superuser app): an alias would hide the secret
  # from the column-name check, so only a security_invoker view, which reads as thecore_raw, is open.
  it "denies views and materialized views that read as their owner, and opens security_invoker views" do
    conn.execute("CREATE VIEW raw_grants_hashes AS SELECT id, encrypted_password AS digest FROM users")
    conn.execute("CREATE MATERIALIZED VIEW raw_grants_settings AS SELECT id FROM thecore_settings")
    conn.execute("CREATE VIEW raw_grants_emails WITH (security_invoker = true) AS SELECT id, email FROM users")

    raw_grants

    expect(readable?("raw_grants_hashes", "id")).to be(false)
    expect(readable?("raw_grants_settings", "id")).to be(false)
    expect(readable?("raw_grants_emails", "email")).to be(true)
  end

  it "takes set_config away from thecore_raw" do
    raw_grants

    expect(conn.select_value("SELECT has_function_privilege('thecore_raw', 'pg_catalog.set_config(text, text, boolean)', 'EXECUTE')")).to be(false)
    expect(RawSqlGrants.reasons).to eq([])
  end

  it "is idempotent" do
    raw_grants
    expect { raw_grants }.not_to raise_error
    expect(RawSqlGrants.protected?).to be(true)
  end

  context "when the database user is not superuser" do
    before do
      conn.execute("CREATE ROLE raw_grants_app NOLOGIN NOSUPERUSER")
      conn.execute("SET LOCAL SESSION AUTHORIZATION raw_grants_app")
    end

    it "does not fail, warns, and leaves the protection reported as reduced" do
      allow(Rails.logger).to receive(:warn)

      expect { raw_grants }.not_to raise_error

      expect(Rails.logger).to have_received(:warn).with(/not superuser/)
      expect(RawSqlGrants.protected?).to be(false)
      expect(RawSqlGrants.reasons).to include("role_not_usable").or eq(["role_missing"])
    end
  end

  describe "RawSqlGrants.report_at_boot" do
    before { allow(Rails.logger).to receive(:warn) }

    it "warns with the reasons when the protection is reduced" do
      raw_grants
      conn.execute("GRANT EXECUTE ON FUNCTION pg_catalog.set_config(text, text, boolean) TO PUBLIC")

      RawSqlGrants.report_at_boot

      expect(Rails.logger).to have_received(:warn).with(/reduced protection.*set_config_executable/)
    end

    it "says nothing when the protection is full" do
      raw_grants

      RawSqlGrants.report_at_boot

      expect(Rails.logger).not_to have_received(:warn)
    end

    it "never stops the boot when the database cannot be asked" do
      allow(RawSqlGrants).to receive(:reasons).and_raise(ActiveRecord::ConnectionNotEstablished)

      expect { RawSqlGrants.report_at_boot }.not_to raise_error
      expect(Rails.logger).to have_received(:warn).with(/could not be checked/)
    end
  end

  it "runs at the end of thecore:db:seed, which thecore:db:update and the image entrypoint run" do
    allow(Rails::Engine).to receive(:subclasses).and_return([])
    allow(Rake::Task["db:seed"]).to receive(:invoke) { expect(RawSqlGrants).not_to have_received(:apply!) }
    allow(RawSqlGrants).to receive(:apply!).and_return(:applied)

    seed = Rake::Task["thecore:db:seed"]
    seed.reenable
    seed.invoke

    expect(RawSqlGrants).to have_received(:apply!)
  end
end
