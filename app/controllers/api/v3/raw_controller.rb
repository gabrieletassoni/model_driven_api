# POST|GET /api/v3/raw/sql: the rows of one SELECT as a plain JSON array (ADR 0004). Executed by
# SafeSqlExecutor (host ADR 0048, Odoo #5835): 422 for a rejected or failed query, 413 for a result
# over RAW_SQL_MAX_RESULT_BYTES, never with PostgreSQL's message.
class Api::V3::RawController < Api::V3::ApplicationController
  skip_before_action :extract_model

  def sql
    return render json: {error: "Query is required"}, status: 400 if params[:query].nil?

    result = SafeSqlExecutor.execute_select(params[:query].to_s, correlation_id: request.request_id)
    render json: result, status: 200
  rescue SafeSqlExecutor::Error => e
    render json: e, status: e.http_status
  rescue ArgumentError, ActiveRecord::StatementInvalid => e
    # Only the RAW_SQL_ENFORCE=false fallback raises these, answered as before ADR 0048.
    render json: {error: e.message}, status: 400
  end
end
