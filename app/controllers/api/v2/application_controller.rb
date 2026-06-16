class Api::V2::ApplicationController < ActionController::API
  # Detect Locale from Accept-Language headers
  include HttpAcceptLanguage::AutoLocale
  # Actions will be authorized directly in the action
  include CanCan::ControllerAdditions
  include ::ApiExceptionManagement

  attr_accessor :current_user

  before_action :authenticate_request
  before_action :extract_model
  before_action :find_record, only: [:show, :destroy, :update, :patch]

  # GET :controller/
  def index
    authorize! :index, @model unless public_custom_action?

    # Custom Action
    status, result, status_number = check_for_custom_action
    return render json: result, status: (status_number.presence || 200) if status == true

    # Normal Index Action with Ransack querying
    # Keeping this automation can be too dangerous and lead to unpredicted results
    # TODO: Remove it
    # @q = (@model.column_names.include?("user_id") ? @model.where(user_id: current_user.id) : @model).ransack(@query.presence|| params[:q])
    Rails.logger.debug("Querying for #{@model} with #{@query}: #{@query.presence || params[:q]}")
    @q = @model.ransack(@query.presence || params[:q])
    page = (@page.presence || params[:page])
    per = (@per.presence || params[:per])
    # pages_info = (@pages_info.presence || params[:pages_info])
    count = (@count.presence || params[:count])
    @records_count = @q.result.length
    Rails.logger.debug("Found #{@records_count.inspect} records")
    @records_all = @q.result
    # Pagination
    @records = @q.result.page(page).per(per) # (distinct: true) Removing, but I'm not sure, with it I cannot sort in postgres for associated records (throws an exception on misuse of sort with distinct)
    # Content-Range: posts 0-4/27
    range_start = [(page.to_i - 1) * per.to_i, 0].max
    range_end = [0, page.to_i * per.to_i - 1].max
    response.set_header("Content-Range", "#{@model.table_name} #{range_start}-#{range_end}/#{@records.total_count}")

    # puts "ALL RECORDS FOUND: #{@records_all.inspect}"
    status = @records_count.zero? && params[:always_ok].blank? ? 404 : 200
    # puts "If it's asked for page number, then paginate"
    return render json: @records.as_json(json_attrs), status: status if !page.blank? # (@json_attrs || {})
    #puts "if you ask for count, then return a json object with just the number of objects"
    return render json: { count: @records_count } if !count.blank?
    #puts "Default"
    json_out = @records_all.as_json(json_attrs)
    #puts "JSON ATTRS: #{json_attrs}"
    #puts "JSON OUT: #{json_out}"
    render json: json_out, status: status #(@json_attrs || {})
  end

  def show
    authorize! :show, @record_id.presence || @model

    # Custom Show Action
    status, result, status_number = check_for_custom_action
    return render json: result, status: (status_number.presence || 200) if status == true

    # Normal Show
    result = @record.to_json(json_attrs)
    render json: result, status: 200
  end

  def create
    # Normal Create Action
    Rails.logger.debug("Creating a new record #{@record}")
    authorize! :create, @record.presence || @model unless public_custom_action?
    # Custom Action
    status, result, status_number = check_for_custom_action
    return render json: result, status: (status_number.presence || 200) if status == true
    # Keeping this automation can be too dangerous and lead to unpredicted results
    # TODO: Remove it
    # @record.user_id = current_user.id if @model.column_names.include? "user_id"
    @record = @model.new(@body)
    @record.save!
    render json: @record.to_json(json_attrs), status: 201
  end

  def update
    authorize! :update, @record.presence || @model

    # Custom Action
    status, result, status_number = check_for_custom_action
    return render json: result, status: (status_number.presence || 200) if status == true

    # Normal Update Action
    # Use save! to be sure to raise an exception if the record is not valid and to trigger all the callbacks for the model during update
    Rails.logger.debug("############################## Updating record #{@record}")
    @record.update!(@body)

    render json: @record.to_json(json_attrs), status: 200
  end

  # Define the path method as an alias to the update one, they are basically the same method
  alias_method :patch, :update

  def update_multi
    authorize! :update, @model
    ids = params[:ids].split(",")
    @model.where(id: ids).update!(@body)
    render json: ids.to_json, status: 200
  end

  def destroy
    authorize! :destroy, @record.presence || @model

    # Custom Action
    status, result, status_number = check_for_custom_action
    return render json: result, status: (status_number.presence || 200) if status == true

    # Normal Destroy Action
    return api_error(status: 500) unless @record.destroy
    head :ok
  end

  def destroy_multi
    authorize! :destroy, @model

    # Normal Destroy Action
    ids = params[:ids].split(",")
    @model.where(id: ids).destroy!(@body)
    render json: ids.to_json, status: 200
  end

  private

  # Returns true if the current request is for a NonCrudEndpoints custom action
  # that has been declared as public (no authentication required).
  # Forces autoloading of the Endpoints::<Model> class so the public_action_registry
  # is populated before authenticate_request checks it.
  def public_custom_action?
    return false unless request.url.include?("/custom_action/")
    model_name = params[:ctrl].to_s.classify
    action_name = params[:action_name].to_s
    # Ensure the endpoint class is loaded so its public_action declarations are registered.
    ("Endpoints::#{model_name}".constantize rescue nil)
    NonCrudEndpoints.public_action?(model_name, action_name)
  end

  ## CUSTOM ACTION
  # [GET|PUT|POST|DELETE] :controller?do=:custom_action
  # or
  # [GET|PUT|POST|DELETE] :controller/:id?do=:
  # or
  # [GET|PUT|POST|DELETE] :controller?do=:custom_action-token
  # or
  # [GET|PUT|POST|DELETE] :controller/:id?do=:custom_action-token
  # or
  # [GET|PUT|POST|DELETE] :controller/custom_action/:custom_action
  # or
  # [GET|PUT|POST|DELETE] :controller/custom_action/:custom_action/:id
  def check_for_custom_action
    dispatched, body, status = Api::CustomActionDispatcher.call(@model, params, request)
    return false unless dispatched
    [true, body.to_json(json_attrs), status]
  end

  def bearer_token
    pattern = /^Bearer /
    header = request.headers["Authorization"]
    header.gsub(pattern, "") if header && header.match(pattern)
  end

  def class_exists?(class_name)
    klass = Module.const_get(class_name)
    return klass.is_a?(Class)
  rescue NameError
    return false
  end

  def authenticate_request
    # Skip auth for public NonCrudEndpoints actions (e.g. vapid_public_key).
    return if public_custom_action?

    @current_user = nil
    Settings.ns(:security).allowed_authorization_headers.split(",").each do |header|
      # puts "Found header #{header}: #{request.headers[header]}"
      check_authorization("Authorize#{header}".constantize.call(request)) unless @current_user
    end

    Rails.logger.debug("Checking for authorization with AuthorizeApiRequest if current_user not already present -> current_user: #{@current_user}")

    check_authorization AuthorizeApiRequest.call(request) unless @current_user
    return unauthenticated!(OpenStruct.new({ message: @auth_errors })) unless @current_user

    current_user = @current_user
    params[:current_user_id] = @current_user.id
    # Now every time the user fires off a successful GET request,
    # a new token is generated and passed to them, and the clock resets.
    response.set_header("Token", JsonWebToken.encode(user_id: current_user.id))
  end

  def find_record
    record_id ||= (params[:path].split("/").second.to_i rescue nil)
    # Keeping this automation can be too dangerous and lead to unpredicted results
    # TODO: Remove it
    # @record = @model.column_names.include?("user_id") ? @model.where(id: (record_id.presence || @record_id.presence || params[:id]), user_id: current_user.id).first : @model.find((@record_id.presence || params[:id]))
    @record = @model.find((@record_id.presence || params[:id]))
    return not_found! if @record.blank?
  end

  def json_attrs
    # In order of importance: if you send the configuration via querystring you are ok
    # has precedence over if you have setup the json_attrs in the model concern
    from_params = params[:a].deep_symbolize_keys unless params[:a].blank?
    from_params = params[:json_attrs].deep_symbolize_keys unless params[:json_attrs].blank?
    from_params.presence || @json_attrs.presence || @model.json_attrs.presence || {} rescue {}
  end

  def extract_model
    @model = Api::ModelResolver.resolve(params, controller_path, controller_name)
    @body = (params[@model.model_name.singular].presence || params[@model.model_name.route_key]) rescue params
  rescue Api::ModelResolver::NotFound
    not_found!
  end

  def check_authorization(cmd)
    Rails.logger.debug("Checking authorization: #{cmd.inspect}")
    if cmd.success?
      @current_user = cmd.result
    else
      @auth_errors = cmd.errors
    end
  end

  # Nullifying strong params for API
  def params
    request.parameters
  end
end
