require "pg_query"
require "securerandom"

# Runs the SQL string of POST /api/v2|v3/raw/sql, sent by any authenticated user (host ADR 0048,
# Odoo #5835). What makes it safe is not who may call it but what the query can do:
#
# 1. PostgreSQL's own parser (pg_query) accepts exactly one plain SELECT: no INTO, no
#    FOR UPDATE/SHARE, no INSERT/UPDATE/DELETE/MERGE anywhere in the tree (CTEs included), and none
#    of DENIED_FUNCTIONS. It is the second line, there for a clear 422: SQL hidden in strings
#    (query_to_xml) escapes any parser.
# 2. The query runs in a transaction of its own: READ ONLY, statement/lock timeouts, work_mem and
#    temp_file_limit, through select_all (one statement over exec_params, never execute), and is
#    always rolled back. Session advisory locks survive a rollback, so pg_advisory_unlock_all()
#    runs afterwards. When RawSqlGrants.protected?, the query runs as the thecore_raw role
#    (Odoo #6093), which cannot read secret tables and columns nor call set_config: that, not the
#    parser, is what keeps secrets out of reach.
#
# Errors never carry PostgreSQL's message: the caller gets Rejected/Failed with a reason, the
# details go to the Rails log tagged with the correlation id (the request id).
#
# RAW_SQL_ENFORCE=false (rollout switch, per installation): a rejection (parser, size, privileges,
# READ ONLY) is logged as IntegrationLog :warning (when the host has that model) and the query runs
# again the old way, so a frontend not verified yet keeps working while the logs show what the new
# rules would break. Failures (timeout, SQL error, oversize result) are never rerun: the old way
# would only run an expensive query again without any limit.
module SafeSqlExecutor
  # The response body's "error" is +kind+; "reason" says why, without schema details.
  class Error < StandardError
    attr_reader :reason, :sqlstate

    def initialize(reason, sqlstate: nil)
      @reason = reason
      @sqlstate = sqlstate
      super(reason)
    end

    def as_json(*)
      {"error" => kind, "reason" => reason, "sqlstate" => sqlstate}.compact
    end

    # The v3 status; v2 answers 400 for every error.
    def http_status
      422
    end
  end

  # The query is not allowed: refused by the parser, by its size, or by the database's privileges.
  class Rejected < Error
    def kind
      "raw_sql_rejected"
    end
  end

  # An allowed query that could not complete: timeout, SQL error, nested call.
  class Failed < Error
    def kind
      "raw_sql_failed"
    end
  end

  # The rows exceed RAW_SQL_MAX_RESULT_BYTES.
  class ResultTooLarge < Failed
    def initialize
      super("result_too_large")
    end

    def http_status
      413
    end
  end

  # Called with no or the wrong arguments these still have effects that READ ONLY doesn't stop
  # or that outlive the transaction (host research raw-sql-safe-execution.md §2.2, §2.4).
  DENIED_FUNCTIONS = %w[
    set_config
    pg_advisory_lock pg_advisory_lock_shared pg_try_advisory_lock pg_try_advisory_lock_shared
    pg_advisory_unlock pg_advisory_unlock_shared pg_advisory_unlock_all
    lo_create lo_creat lo_open lo_write lowrite lo_put lo_from_bytea lo_unlink lo_truncate
    lo_truncate64 lo_import lo_export
    pg_terminate_backend pg_cancel_backend
    pg_sleep pg_sleep_for pg_sleep_until
    pg_notify
  ].freeze

  DML_NODES = [PgQuery::InsertStmt, PgQuery::UpdateStmt, PgQuery::DeleteStmt, PgQuery::MergeStmt].freeze

  # Each overridable with RAW_SQL_<NAME> (ADR 0048 §6).
  DEFAULTS = {
    statement_timeout: "15s",
    lock_timeout: "1s",
    work_mem: "16MB",
    temp_file_limit: "256MB",
    max_query_bytes: 100 * 1024,
    max_result_bytes: 10 * 1024 * 1024
  }.freeze

  # SQLSTATEs that mean "not allowed" rather than "broken query": insufficient privilege,
  # read-only transaction.
  NOT_PERMITTED = %w[42501 25006].freeze
  # query_canceled (statement_timeout), lock_not_available (lock_timeout).
  TIMEOUT = %w[57014 55P03].freeze

  module_function

  # Rows of the query as an Array of Hashes. Raises Rejected or Failed; with RAW_SQL_ENFORCE=false
  # the legacy path's errors (ArgumentError, ActiveRecord::StatementInvalid) come through as before.
  def execute_select(query, correlation_id: nil)
    correlation_id ||= SecureRandom.uuid
    validate!(query)
    run(query, correlation_id)
  rescue Error => e
    Rails.logger.warn("[raw_sql #{correlation_id}] #{e.kind} #{e.reason}")
    raise if e.is_a?(Failed) || enforce?

    log_unenforced(query, e, correlation_id)
    legacy_execute(query)
  end

  def enforce?
    ENV.fetch("RAW_SQL_ENFORCE", "true").strip.downcase != "false"
  end

  # RAW_SQL_<NAME>, or the default. A byte cap that isn't an integer falls back to the default (with
  # a warning) rather than break every query; a bad GUC value is PostgreSQL's to refuse.
  def setting(name)
    default = DEFAULTS.fetch(name)
    value = ENV["RAW_SQL_#{name.to_s.upcase}"].presence
    return default if value.nil?
    return value unless default.is_a?(Integer)

    Integer(value, 10)
  rescue ArgumentError
    Rails.logger.warn("[raw_sql] RAW_SQL_#{name.to_s.upcase}=#{value.inspect} is not a byte count, using #{default}")
    default
  end

  def validate!(query)
    raise Rejected, "query_too_large" if query.bytesize > setting(:max_query_bytes)

    parsed = PgQuery.parse(query)
    stmts = parsed.tree.stmts
    raise Rejected, "only_single_select" unless stmts.size == 1 && stmts.first.stmt.select_stmt

    parsed.walk! do |node|
      case node
      when *DML_NODES
        raise Rejected, "data_modifying_statement"
      when PgQuery::SelectStmt
        raise Rejected, "data_modifying_statement" if node.into_clause
        raise Rejected, "locking_clause" if node.locking_clause.any?
      when PgQuery::FuncCall
        name = node.funcname.last&.string&.sval.to_s.downcase
        raise Rejected, "function_not_allowed" if DENIED_FUNCTIONS.include?(name)
      end
    end
  rescue PgQuery::ParseError
    raise Rejected, "syntax_error"
  end

  def run(query, correlation_id)
    conn = ActiveRecord::Base.connection
    # A nested call would only get a savepoint: READ ONLY and the limits must own the transaction.
    raise Failed, "nested_transaction" if conn.transaction_open?

    rows = nil
    begin
      conn.transaction do
        conn.execute("SET TRANSACTION READ ONLY")
        conn.execute("SET LOCAL statement_timeout = #{conn.quote(setting(:statement_timeout))}")
        conn.execute("SET LOCAL lock_timeout = #{conn.quote(setting(:lock_timeout))}")
        conn.execute("SET LOCAL work_mem = #{conn.quote(setting(:work_mem))}")
        # Superuser-only (PGC_SUSET): on an installation where the app isn't superuser it is skipped.
        if RawSqlGrants.superuser?(conn)
          conn.execute("SET LOCAL temp_file_limit = #{conn.quote(setting(:temp_file_limit))}")
        end
        # The barrier that hides secrets (Odoo #6093). Without it (grants never applied, app not
        # superuser) the query still runs READ ONLY with the parser in front, as RawSqlGrants reports.
        conn.execute("SET LOCAL ROLE #{RawSqlGrants::ROLE}") if RawSqlGrants.protected?(conn)
        rows = conn.select_all(query, "RawSql").to_a
        raise ActiveRecord::Rollback
      end
    rescue ActiveRecord::StatementInvalid => e
      raise translate(e, correlation_id)
    ensure
      release_advisory_locks(conn, correlation_id)
    end

    check_result_size!(rows)
    rows
  end

  def check_result_size!(rows)
    size = rows.sum { |row| row.sum { |_, value| value.to_s.bytesize } }
    raise ResultTooLarge if size > setting(:max_result_bytes)
  end

  # Session advisory locks survive the rollback. Guarded: on a broken connection its own error must
  # not replace the query's (whose PostgreSQL message would then reach the controller).
  def release_advisory_locks(conn, correlation_id)
    conn.select_value("SELECT pg_advisory_unlock_all()")
  rescue ActiveRecord::ActiveRecordError => e
    Rails.logger.error("[raw_sql #{correlation_id}] pg_advisory_unlock_all failed: #{e.class}")
  end

  def translate(error, correlation_id)
    sqlstate = error.cause.respond_to?(:result) ? error.cause.result&.error_field(PG::Result::PG_DIAG_SQLSTATE) : nil
    Rails.logger.warn("[raw_sql #{correlation_id}] #{sqlstate} #{error.cause&.message || error.message}")
    if NOT_PERMITTED.include?(sqlstate)
      Rejected.new("not_permitted")
    elsif TIMEOUT.include?(sqlstate)
      Failed.new("timeout")
    else
      Failed.new("query_error", sqlstate: sqlstate)
    end
  end

  def log_unenforced(query, error, correlation_id)
    Rails.logger.warn("[raw_sql #{correlation_id}] RAW_SQL_ENFORCE=false: #{error.kind} #{error.reason}, running it the old way")
    return unless defined?(::IntegrationLog)

    ::IntegrationLog.create!(
      severity: "warning",
      description: "raw/sql: #{error.kind} (#{error.reason}), run anyway because RAW_SQL_ENFORCE=false",
      data: {correlation_id: correlation_id, reason: error.reason, query: query.truncate(10_000)}
    )
  rescue => e
    Rails.logger.error("[raw_sql #{correlation_id}] IntegrationLog not written: #{e.class}")
  end

  # The pre-ADR 0048 behaviour, reached only with RAW_SQL_ENFORCE=false.
  def legacy_execute(query)
    unless query.strip.gsub(/\s+/, " ").upcase.match?(/^(WITH .+)?SELECT /)
      raise ArgumentError, "Only SELECT queries (including with CTEs) are allowed"
    end

    ActiveRecord::Base.connection.execute(query).to_a
  end
end
