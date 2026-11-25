# The thecore_raw database role under which SafeSqlExecutor runs the SQL of POST /api/v2|v3/raw/sql
# (host ADR 0048, Odoo #6093). The parser cannot see SQL hidden in a string (query_to_xml), so the
# barrier that keeps secrets out of reach is the role's privileges:
#
# - thecore_raw is NOLOGIN NOINHERIT and can only SELECT;
# - no privilege on EXCLUDED_TABLES;
# - on any table or view with a column whose name looks like a secret (SECRET_COLUMN), a per-column
#   grant that leaves those columns out, so SELECT * or a whole-row json_agg of users is refused;
# - every other table is readable, and ALTER DEFAULT PRIVILEGES keeps new tables readable;
# - a view or materialized view reads with its owner's privileges (the superuser app), so an alias
#   would slip a secret past the column-name check: only a security_invoker view is readable;
# - EXECUTE on SafeSqlExecutor::DENIED_FUNCTIONS revoked from PUBLIC (set_config above all: from a
#   superuser session it would undo SET LOCAL ROLE).
#
# apply! is idempotent and rebuilds all of it from scratch, so it runs at every deploy (rake
# thecore:db:raw_grants, after thecore:db:seed): new non-secret columns become readable, new secret
# ones disappear, and a manual change to these privileges does not survive.
#
# Without superuser rights it cannot revoke set_config, so it changes nothing, logs a warning and
# returns :skipped: the deploy goes on and the executor runs without the role (protected? is false,
# reported at boot and by GET /api/v2|v3/info/raw_sql).
module RawSqlGrants
  ROLE = "thecore_raw"

  EXCLUDED_TABLES = %w[
    ldap_servers thecore_settings used_tokens push_subscribers action_mailbox_inbound_emails integration_logs
  ].freeze

  # Rails' filter_parameters patterns without email, which frontends read and which is not a secret.
  SECRET_COLUMN = /passw|secret|token|_key|crypt|salt|certificate|otp|ssn|cvv|cvc/i

  # Tables, partitioned tables, foreign tables, plus views that read as the caller
  # (security_invoker, PostgreSQL 15+). Other views and materialized views are left out.
  READABLE_RELATIONS = <<~SQL
    (c.relkind IN ('r', 'p', 'f') OR (c.relkind = 'v' AND EXISTS (
      SELECT 1 FROM unnest(c.reloptions) o
      WHERE lower(o) IN ('security_invoker=true', 'security_invoker=on', 'security_invoker=1', 'security_invoker=yes'))))
  SQL

  module_function

  # :applied, or :skipped when the connection is not superuser.
  def apply!(conn = ActiveRecord::Base.connection)
    unless superuser?(conn)
      Rails.logger.warn("[raw_sql] #{ROLE} grants not applied: the database user is not superuser. " \
        "raw/sql runs without the role and cannot hide secrets (host ADR 0048 §9).")
      return :skipped
    end

    conn.transaction do
      ensure_role(conn)
      grant_tables(conn)
      revoke_functions(conn)
    end
    :applied
  end

  # True when SafeSqlExecutor can SET LOCAL ROLE thecore_raw and the role cannot undo it.
  def protected?(conn = ActiveRecord::Base.connection)
    reasons(conn).empty?
  end

  # What GET /api/v2|v3/info/raw_sql answers.
  def status(conn = ActiveRecord::Base.connection)
    found = reasons(conn)
    {protection: found.empty? ? "full" : "reduced", reasons: found, enforce: SafeSqlExecutor.enforce?}
  end

  # Why the protection is reduced: [] when it is complete.
  def reasons(conn = ActiveRecord::Base.connection)
    return ["role_missing"] unless conn.select_value("SELECT 1 FROM pg_roles WHERE rolname = #{conn.quote(ROLE)}")

    found = []
    found << "role_not_usable" unless conn.select_value("SELECT pg_has_role(current_user, #{conn.quote(ROLE)}, 'MEMBER')")
    if conn.select_value("SELECT has_function_privilege(#{conn.quote(ROLE)}, 'pg_catalog.set_config(text, text, boolean)', 'EXECUTE')")
      found << "set_config_executable"
    end
    found
  end

  # Called by the engine when a server boots (ADR 0048 §9). Never raises: a database that cannot be
  # asked must not stop the boot.
  def report_at_boot
    found = ActiveRecord::Base.connection_pool.with_connection { |conn| reasons(conn) }
    return if found.empty?

    Rails.logger.warn("[raw_sql] reduced protection (#{found.join(", ")}): raw/sql runs without the " \
      "#{ROLE} role and cannot hide secrets. Run rails thecore:db:raw_grants as a superuser (host ADR 0048).")
  rescue => e
    Rails.logger.warn("[raw_sql] #{ROLE} protection could not be checked at boot: #{e.class}")
  end

  def superuser?(conn)
    conn.select_value("SELECT current_setting('is_superuser')") == "on"
  end

  def ensure_role(conn)
    conn.execute(<<~SQL)
      DO $$ BEGIN
        CREATE ROLE #{ROLE} NOLOGIN NOINHERIT;
      EXCEPTION WHEN duplicate_object THEN NULL;
      END $$
    SQL
    conn.execute("ALTER ROLE #{ROLE} NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS")
  end

  def grant_tables(conn)
    schema = conn.quote_table_name(conn.select_value("SELECT current_schema()"))
    conn.execute("GRANT USAGE ON SCHEMA #{schema} TO #{ROLE}")
    # REVOKE ALL on a table also drops its column grants, so stale ones go too.
    conn.execute("REVOKE ALL ON ALL TABLES IN SCHEMA #{schema} FROM #{ROLE}")
    conn.execute("REVOKE ALL ON ALL SEQUENCES IN SCHEMA #{schema} FROM #{ROLE}")
    conn.execute("ALTER DEFAULT PRIVILEGES IN SCHEMA #{schema} GRANT SELECT ON TABLES TO #{ROLE}")

    columns_by_relation(conn).each do |relation, columns|
      next if EXCLUDED_TABLES.include?(relation)

      table = "#{schema}.#{conn.quote_table_name(relation)}"
      readable = columns.grep_v(SECRET_COLUMN)
      if readable.size == columns.size
        conn.execute("GRANT SELECT ON #{table} TO #{ROLE}")
      elsif readable.any?
        conn.execute("GRANT SELECT (#{readable.map { |c| conn.quote_column_name(c) }.join(", ")}) ON #{table} TO #{ROLE}")
      end
    end
  end

  # { relation name => [column names] } of the relations thecore_raw may read in the current schema. pg_attribute rather than
  # information_schema, which lists only the columns the current user may read.
  def columns_by_relation(conn)
    conn.select_rows(<<~SQL).group_by(&:first).transform_values { |rows| rows.map(&:last) }
      SELECT c.relname, a.attname
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      JOIN pg_attribute a ON a.attrelid = c.oid
      WHERE n.nspname = current_schema() AND #{READABLE_RELATIONS} AND a.attnum > 0 AND NOT a.attisdropped
      ORDER BY c.relname, a.attnum
    SQL
  end

  # Every overload of each denied function in pg_catalog.
  def revoke_functions(conn)
    names = SafeSqlExecutor::DENIED_FUNCTIONS.map { |name| conn.quote(name) }.join(", ")
    conn.select_values(<<~SQL).each do |signature|
      SELECT p.oid::regprocedure::text
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pg_catalog' AND p.proname IN (#{names})
    SQL
      conn.execute("REVOKE EXECUTE ON FUNCTION #{signature} FROM PUBLIC, #{ROLE}")
    end
  end
end
