# require 'model_driven_api/version'
class Api::V2::RawController < Api::V2::ApplicationController
  # Info uses a different auth method: username and password
  # skip_before_action :authenticate_request, only: [:version, :swagger, :openapi], raise: false
  skip_before_action :extract_model
  
  # api :GET, '/api/v2/raw/sql'
  def sql
    query = params[:query]

    render json: SafeSqlExecutor.execute_select(query).first&["json_agg"], status: 200
  end

end
