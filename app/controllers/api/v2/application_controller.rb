class Api::V2::ApplicationController < ActionController::API
    # Detect Locale from Accept-Language headers
    include HttpAcceptLanguage::AutoLocale
    # Actions will be authorized directly in the action
    include CanCan::ControllerAdditions
    include ::ApiExceptionManagement

    attr_accessor :current_user
    
    before_action :authenticate_request
    before_action :extract_model
    before_action :find_record, only: [ :show, :destroy, :update ]
    
    # GET :controller/
    def index
        authorize! :index, @model

        # Custom Action
        status, result, status_number = check_for_custom_action
        return render json: result, status: (status_number.presence || 200) if status == true

        # Normal Index Action with Ransack querying
        # Keeping this automation can be too dangerous and lead to unpredicted results
        # TODO: Remove it
        # @q = (@model.column_names.include?("user_id") ? @model.where(user_id: current_user.id) : @model).ransack(@query.presence|| params[:q])
        @q = @model.ransack(@query.presence|| params[:q])
        @records_all = @q.result # (distinct: true) Removing, but I'm not sure, with it I cannot sort in postgres for associated records (throws an exception on misuse of sort with distinct)
        page = (@page.presence || params[:page])
        per = (@per.presence || params[:per])
        # pages_info = (@pages_info.presence || params[:pages_info])
        count = (@count.presence || params[:count])
        # Pagination
        @records = @records_all.page(page).per(per)
        # Content-Range: posts 0-4/27
        range_start = [(page.to_i - 1) * per.to_i, 0].max;
        range_end = [0, page.to_i * per.to_i - 1].max;
        response.set_header('Content-Range', "#{@model.table_name} #{range_start}-#{range_end}/#{@records.total_count}")
        
        # If there's the keyword pagination_info, then return a pagination info object
        # return render json: {count: @records_all.count,current_page_count: @records.count,next_page: @records.next_page,prev_page: @records.prev_page,is_first_page: @records.first_page?,is_last_page: @records.last_page?,is_out_of_range: @records.out_of_range?,pages_count: @records.total_pages,current_page_number: @records.current_page } if !pages_info.blank?
        
        # puts "ALL RECORDS FOUND: #{@records_all.inspect}"
        status = @records_all.blank? ? 404 : 200
        # puts "If it's asked for page number, then paginate"
        return render json: @records.as_json(json_attrs), status: status if !page.blank? # (@json_attrs || {})
        #puts "if you ask for count, then return a json object with just the number of objects"
        return render json: {count: @records_all.count}if !count.blank?
        #puts "Default"
        json_out = @records_all.as_json(json_attrs)
        #puts "JSON ATTRS: #{json_attrs}"
        #puts "JSON OUT: #{json_out}"
        render json: json_out, status: status #(@json_attrs || {})
    end
    
    def show
        authorize! :show, @record_id

        # Custom Show Action
        status, result, status_number = check_for_custom_action
        return render json: result, status: (status_number.presence || 200) if status == true

        # Normal Show
        result = @record.to_json(json_attrs)
        render json: result, status: 200
    end
    
    def create
        # Normal Create Action
        @record = @model.new(@body)
        authorize! :create, @record
        # Custom Action
        status, result, status_number = check_for_custom_action
        return render json: result, status: (status_number.presence || 200) if status == true
        # Keeping this automation can be too dangerous and lead to unpredicted results
        # TODO: Remove it
        # @record.user_id = current_user.id if @model.column_names.include? "user_id"
        @record.save!
        render json: @record.to_json(json_attrs), status: 201
    end
    
    def update
        authorize! :update, @record

        # Custom Action
        status, result, status_number = check_for_custom_action
        return render json: result, status: (status_number.presence || 200) if status == true

        # Normal Update Action
        # Rails 6 vs Rails 6.1
        @record.respond_to?('update_attributes!') ? @record.update_attributes!(@body) : @record.update!(@body)
        render json: @record.to_json(json_attrs), status: 200
    end

    def update_multi
        authorize! :update, @model
        ids = params[:ids].split(",")
        @model.where(id: ids).update!(@body)
        render json: ids.to_json, status: 200
    end
    
    def destroy
        authorize! :destroy, @record

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

    def check_for_custom_action
        ## CUSTOM ACTION
        # [GET|PUT|POST|DELETE] :controller?do=:custom_action
        # or
        # [GET|PUT|POST|DELETE] :controller/:id?do=:custom_action
        unless params[:do].blank?
            # Poor man's solution to avoid the possibility to 
            # call an unwanted method in the AR Model.
            resource = "custom_action_#{params[:do]}"
            raise NoMethodError unless @model.respond_to?(resource)
            # puts json_attrs
            body, status = @model.send(resource, params)
            return true, body.to_json(json_attrs), status
        end
        # if it's here there is no custom action in the request querystring
        return false
    end

    def class_exists?(class_name)
        klass = Module.const_get(class_name)
        return klass.is_a?(Class)
    rescue NameError
        return false
    end
    
    def authenticate_request
        @current_user = nil
        Settings.ns(:security).allowed_authorization_headers.split(",").each do |header|
            # puts "Found header #{header}: #{request.headers[header]}" 
            check_authorization("Authorize#{header}".constantize.call(request.headers)) # if request.headers[header]
        end
        
        check_authorization AuthorizeApiRequest.call(request.headers) unless @current_user
        return unauthenticated!(OpenStruct.new({message: @auth_errors})) unless @current_user
        
        current_user = @current_user
        params[:current_user_id] = @current_user.id
        # Now every time the user fires off a successful GET request, 
        # a new token is generated and passed to them, and the clock resets.
        response.set_header('Token', JsonWebToken.encode(user_id: current_user.id))
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
        # This method is only valid for ActiveRecords
        # For any other model-less controller, the actions must be 
        # defined in the route, and must exist in the controller definition.
        # So, if it's not an activerecord, the find model makes no sense at all
        # thus must return 404.
        @model = (params[:ctrl].classify.constantize rescue params[:path].split("/").first.classify.constantize rescue controller_path.classify.constantize rescue controller_name.classify.constantize rescue nil)
        # Getting the body of the request if it exists, it's ok the singular or 
        # plural form, this helps with automatic tests with Insomnia.
        @body = params[@model.model_name.singular].presence || params[@model.model_name.route_key]
        # Only ActiveRecords can have this model caputed 
        return not_found! if (!@model.new.is_a? ActiveRecord::Base rescue false)
    end

    def check_authorization cmd
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
