# require 'model_driven_api/version'
class Api::V2::RawController < Api::V2::ApplicationController
  # Info uses a different auth method: username and password
  # skip_before_action :authenticate_request, only: [:version, :swagger, :openapi], raise: false
  skip_before_action :extract_model
  
  # api :GET, '/api/v2/raw/sql'
  def sql
    # if params is nil, render 400
    render json: { error: "Query is required" }, status: 400 and return if params[:query].nil?

    query = params[:query]

    first_element = SafeSqlExecutor.execute_select(query).first rescue nil

    # Error if first_element does not contain a key called results
    render json: { error: "Query must return a key called result" }, status: 400 and return if first_element.nil? || !first_element.key?("result")

    render json: first_element["result"], status: 200
  end

end
