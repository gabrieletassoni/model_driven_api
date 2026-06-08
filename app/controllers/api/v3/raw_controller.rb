class Api::V3::RawController < Api::V3::ApplicationController
  skip_before_action :extract_model

  def sql
    return render json: { error: "Query is required" }, status: 400 if params[:query].nil?

    result = SafeSqlExecutor.execute_select(params[:query]).to_a
    render json: result, status: 200
  rescue ArgumentError => e
    render json: { error: e.message }, status: 400
  rescue ActiveRecord::StatementInvalid => e
    render json: { error: e.message }, status: 400
  end
end
