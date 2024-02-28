# require 'model_driven_api/version'
class Api::V2::InfoController < Api::V2::ApplicationController
  # Info uses a different auth method: username and password
  skip_before_action :authenticate_request, only: [:version], raise: false
  skip_before_action :extract_model
  
  # api :GET, '/api/v2/info/version', "Just prints the APPVERSION."
  def version
    render json: { version: "TODO: Find a Way to Dynamically Obtain It" }.to_json, status: 200
  end

  # api :GET, '/api/v2/info/roles'
  # it returns the roles list
  def roles
    render json: ::Role.all.to_json, status: 200
  end


  # api :GET, '/api/v2/info/heartbeat'
  # Just keeps the session alive by returning a new token
  def heartbeat
    head :ok
  end

  # GET '/api/v2/info/translations'
  def translations
    render json: I18n.t(".", locale: (params[:locale].presence || :it)).to_json, status: 200
  end

  # GET '/api/v2/info/schema'
  def schema
    pivot = {}
    # if Rails.env.development?
    #   Rails.configuration.eager_load_namespaces.each(&:eager_load!) if Rails.version.to_i == 5 #Rails 5
    #   Zeitwerk::Loader.eager_load_all if Rails.version.to_i >= 6 #Rails 6
    # end
    ApplicationRecord.subclasses.each do |d|
      # Only if current user can read the model
      if can? :read, d
        model = d.to_s.underscore.tableize
        pivot[model] ||= {}
        d.columns_hash.each_pair do |key, val| 
          pivot[model][key] = val.type unless key.ends_with? "_id"
        end
        # Only application record descendants to have a clean schema
        pivot[model][:associations] ||= {
          has_many: d.reflect_on_all_associations(:has_many).map { |a| 
            a.name if (((a.options[:class_name].presence || a.name).to_s.classify.constantize.new.is_a? ApplicationRecord) rescue false)
          }.compact, 
          belongs_to: d.reflect_on_all_associations(:belongs_to).map { |a| 
            a.name if (((a.options[:class_name].presence || a.name).to_s.classify.constantize.new.is_a? ApplicationRecord) rescue false)
          }.compact
        }
        pivot[model][:methods] ||= (d.instance_methods(false).include?(:json_attrs) && !d.json_attrs.blank?) ? d.json_attrs[:methods] : nil
      end
    end
    render json: pivot.to_json, status: 200
  end

  def compute_type(model, key)
    # if it's a file, a date or a text, then return string
    instance = model.new
    method_class = instance.send(key).class.to_s
    method_key = model.columns_hash[key]
    return "object" if method_class == "ActiveStorage::Attached::One"
    return "array" if method_class == "ActiveStorage::Attached::Many"
    return "array" if method_class == "Array"
    return "array" if method_class.ends_with? "Array"
    return "array" if method_class.ends_with? "Collection"
    return "array" if method_class.ends_with? "Relation"
    return "array" if method_class.ends_with? "Set"
    return "array" if method_class.ends_with? "List"
    return "array" if method_class.ends_with? "Queue"
    return "array" if method_class.ends_with? "Stack"
    return "array" if method_class.ends_with? "ActiveRecord_Associations_CollectionProxy"
    return "string" if method_key.type == :date
    return "string" if method_key.type == :datetime
    return "string" if method_key.type == :text
    return "object" if method_key.type == :json
    return "object" if method_key.type == :jsonb
    return "string" if method_key.type == :hstore
    return "array" if method_key.type == :enum
    method_key.type
  end

  def create_properties_from_model(model)
    JSON.parse(model.new.to_json(model.json_attrs)).keys.map do |k|
      type = compute_type(model, k)
      if type == "object"
        [k, { "type": "object", "properties": create_properties_from_model(k.classify.constantize) }]
      elsif type == "array"
        [k, { "type": "array", "items": { "type": "object", "properties": create_properties_from_model(k.classify.constantize) } }]
      else
        [k, { "type": type }]
      end
    end.to_h
  end
  
  def generate_paths
    pivot = {
      "/authenticate": {
        "post": {
          "summary": "Authenticate",
          "description": "Authenticate the user and return a JWT token in the header and the current user as body",
          "security": [
            "basicAuth": []
          ],
          "requestBody": {
            "content": {
              "application/json": {
                "schema": {
                  "type": "object",
                  "properties": {
                    "email": {
                      "type": "string",
                      "format": "email"
                    },
                    "password": {
                      "type": "string",
                      "format": "password"
                    }
                  },
                  "required": ["email", "password"]
                }
              }
            }
          },
          "responses": {
            "200": {
              "description": "User authenticated",
              "headers": {
                "token": {
                  "description": "JWT",
                  "schema": {
                    "type": "string"
                  }
                }
              },
              "content": {
                "application/json": {
                  "schema": {
                    "type": "object",
                    # ["id", "email", "created_at", "admin", "locked", "supplier_id", "location_id", "roles"]
                    "properties": create_properties_from_model(User)
                  }
                }
              }
            },
            "401": {
              "description": "Unauthorized"
            }
          }
        }
      }
    }
    # ApplicationRecord.subclasses.each do |d|
    #   # Only if current user can read the model
    #   if can? :read, d
    #     model = d.to_s.underscore.tableize
    #     pivot["/#{model}"] ||= {}
    #     d.columns_hash.each_pair do |key, val| 
    #       pivot[model][key] = val.type unless key.ends_with? "_id"
    #     end
    #     # Only application record descendants in order to have a clean schema
    #     pivot[model][:associations] ||= {
    #       has_many: d.reflect_on_all_associations(:has_many).map { |a| 
    #         a.name if (((a.options[:class_name].presence || a.name).to_s.classify.constantize.new.is_a? ApplicationRecord) rescue false)
    #       }.compact, 
    #       belongs_to: d.reflect_on_all_associations(:belongs_to).map { |a| 
    #         a.name if (((a.options[:class_name].presence || a.name).to_s.classify.constantize.new.is_a? ApplicationRecord) rescue false)
    #       }.compact
    #     }
    #     pivot[model][:methods] ||= (d.instance_methods(false).include?(:json_attrs) && !d.json_attrs.blank?) ? d.json_attrs[:methods] : nil
    #   end
    # end
    pivot
  end

  # GET '/api/v2/info/schema'
  def openapi
    uri = URI(request.url)
    pivot = {
      "openapi": "3.0.0",
      "info": {
        "title": "#{Settings.ns(:main).app_name} API",
        "description": "Model Driven Backend API created to reflect the actual Active Record Models present in the project in a dynamic way",
        "version": "v2"
      },
      "servers": [
        {
          # i.e. "http://localhost:3001/api/v2"
          "url": "#{uri.scheme}://#{uri.host}#{":#{uri.port}" if uri.port.present?}/api/v2",
          "description": "The URL at which this API responds."
        }
      ],
      # 1) Define the security scheme type (HTTP bearer)
      "components":{
        "securitySchemes": {
          "basicAuth": {
            "type": "http",
            "scheme": "basic"
          },
          "bearerAuth": { # arbitrary name for the security scheme
            "type": "http",
            "scheme": "bearer",
            "bearerFormat": "JWT" # optional, arbitrary value for documentation purposes
          }
        }
      },
      # 2) Apply the security globally to all operations
      "security": [
        {
          "bearerAuth": [] # use the same name as above
        }
      ],
      "paths": generate_paths
    }
    
    render json: pivot.to_json, status: 200
  end

  alias swagger openapi

  # GET '/api/v2/info/dsl'
  def dsl
    pivot = {}
    ApplicationRecord.subclasses.each do |d|
      # Only if current user can read the model
      if can? :read, d
        model = d.to_s.underscore.tableize
        pivot[model] = (d.instance_methods(false).include?(:json_attrs) && !d.json_attrs.blank?) ? d.json_attrs : nil
      end
    end
    render json: pivot.to_json, status: 200
  end

  def settings
    render json: ThecoreSettings::Setting.pluck(:ns, :key, :raw).inject({}){|result, array| (result[array.first] ||= {})[array.second] = array.third; result }.to_json, status: 200
  end

end
