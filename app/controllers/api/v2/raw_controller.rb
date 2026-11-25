# POST|GET /api/v2/raw/sql: one SELECT that returns a column called "result" (typically json_agg),
# answered as that value. Executed by SafeSqlExecutor (host ADR 0048, Odoo #5835). Every error is
# 400, as it always was in v2, with a body { error, reason } that never carries PostgreSQL's message.
class Api::V2::RawController < Api::V2::ApplicationController
  skip_before_action :extract_model

  def sql
    render json: {error: "Query is required"}, status: 400 and return if params[:query].nil?

    first_element = begin
      SafeSqlExecutor.execute_select(params[:query].to_s, correlation_id: request.request_id).first
    rescue SafeSqlExecutor::Error => e
      render json: e, status: 400 and return
    rescue ArgumentError, ActiveRecord::StatementInvalid
      # Only the RAW_SQL_ENFORCE=false fallback raises these: v2 always answered them like this.
      nil
    end

    render json: {error: "Query must return a key called result"}, status: 400 and return if first_element.nil? || !first_element.key?("result")

    render json: first_element["result"], status: 200
  end
end
