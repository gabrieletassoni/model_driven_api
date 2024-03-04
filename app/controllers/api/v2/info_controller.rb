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
    # If it's a method, it is a peculiar case, in which we have to return "object" and additionalProperties: true
    return "method" if model.methods.include?(:json_attrs) && model.json_attrs && model.json_attrs.include?(:methods) && model.json_attrs[:methods].include?(key.to_sym)
    # If it's not the case of a method, then it's a field
    method_class = instance.send(key).class.to_s
    method_key = model.columns_hash[key]
    
    # Not columns
    return "object" if method_class == "ActiveStorage::Attached::One"
    return "array" if method_class == "ActiveStorage::Attached::Many" || method_class == "Array" || method_class.ends_with?("Array") || method_class.ends_with?("Collection") || method_class.ends_with?("Relation") || method_class.ends_with?("Set") || method_class.ends_with?("List") || method_class.ends_with?("Queue") || method_class.ends_with?("Stack") || method_class.ends_with?("ActiveRecord_Associations_CollectionProxy")
    
    # Columns
    case method_key.type
    when :json, :jsonb
      return "object"
    when :enum
      return "array"
    when :text, :hstore
      return "string"
    when :decimal, :float, :bigint
      return "number"
    end
    method_key.type.to_s
  end

  def create_properties_from_model(model, dsl)
    JSON.parse(model.new.to_json(dsl)).keys.map do |k|
      # Rails.logger.debug "###################### Model #{model.model_name.human rescue ""} Key #{k}"
      type = compute_type(model, k)
      # Rails.logger.debug "###################### Model #{model.model_name.human rescue ""} Type for #{k} is #{type}"
      if type == "method"
        [k, { "type": "object", "additionalProperties": true }]
      elsif type == "date"
        [k, { "type": "string", "format": "date" }]
      elsif type == "datetime"
        [k, { "type": "string", "format": "date-time" }]
      elsif type == "object" && (k.classify.constantize rescue false)
        sub_model = k.classify.constantize
        properties = dsl[:include].present? && dsl[:include].include?(k) ? create_properties_from_model(sub_model, dsl[:include][k.to_sym]) : create_properties_from_model(sub_model, {})
        [k, { "type": "object", "properties": properties }] rescue nil
      elsif type == "array" && (k.classify.constantize rescue false)
        sub_model = k.classify.constantize
        properties = dsl[:include].present? && dsl[:include].include?(k) ? create_properties_from_model(sub_model, dsl[:include][k.to_sym]) : create_properties_from_model(sub_model, {})
        [k, { "type": "array", "items": { "type": "object", "properties": properties } }] rescue nil
      else
        [k, { "type": type }]
      end
    end.compact.to_h
  end
  
  def generate_paths
    pivot = {
      "/authenticate": {
        "post": {
          "summary": "Authenticate",
          "tags": ["Authentication"],
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
                    "auth": {
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
                      }
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
                    "properties": create_properties_from_model(User, User.json_attrs)
                  }
                }
              }
            },
            "401": {
              "description": "Unauthorized"
            }
          }
        }
      },
      "/info/version": {
        "get": {
          "summary": "Version",
          "description": "Just prints the APPVERSION",
          "tags": ["Info"],
          "responses": {
            "200": {
              "description": "APPVERSION",
              "content": {
                "application/json": {
                  "schema": {
                    "type": "string"
                  }
                }
              }
            }
          }
        }
      },
      "/info/heartbeat": {
        "get": {
          "summary": "Heartbeat",
          "description": "Just keeps the session alive by returning a new token",
          "tags": ["Info"],
          "security": [
            "bearerAuth": []
          ],
          "responses": {
            "200": {
              "description": "Session alive",
              "headers": {
                "token": {
                  "description": "JWT",
                  "schema": {
                    "type": "string"
                  }
                }
              }
            }
          }
        }
      },
      "/info/roles": {
        "get": {
          "summary": "Roles",
          "description": "Returns the roles list",
          "tags": ["Info"],
          "security": [
            "bearerAuth": []
          ],
          "responses": {
            "200": {
              "description": "Roles list",
              "content": {
                "application/json": {
                  "schema": {
                    "type": "array",
                    "items": {
                      "type": "object",
                      "properties": {
                        "id": {
                          "type": "integer"
                        },
                        "name": {
                          "type": "string"
                        },
                        "description": {
                          "type": "string"
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      },
      "/info/schema": {
        "get": {
          "summary": "Schema",
          "description": "Returns the schema of the models",
          "tags": ["Info"],
          "security": [
            "bearerAuth": []
          ],
          "responses": {
            "200": {
              "description": "Schema of the models",
              "content": {
                "application/json": {
                  "schema": {
                    "type": "array",
                    "items": {
                      "type": "object",
                      "properties": {
                        "id": {
                          "type": "integer"
                        },
                        "created_at": {
                          "type": "string",
                          "format": "date-time"
                        },
                        "updated_at": {
                          "type": "string",
                          "format": "date-time"
                        },
                      }
                    }
                  }
                }
              }
            }
          }
        }
      },
      "/info/dsl": {
        "get": {
          "summary": "DSL",
          "description": "Returns the DSL of the models",
          "tags": ["Info"],
          "security": [
            "bearerAuth": []
          ],
          "responses": {
            "200": {
              "description": "DSL of the models",
              "content": {
                "application/json": {
                  "schema": {
                    "type": "object",
                    "properties": {
                      "id": {
                        "type": "integer"
                      },
                      "created_at": {
                        "type": "string",
                        "format": "date-time"
                      },
                      "updated_at": {
                        "type": "string",
                        "format": "date-time"
                      }
                    }
                  }
                }
              }
            }
          }
        }
      },
      "/info/translations": {
        "get": {
          "summary": "Translations",
          "description": "Returns the translations of the entire App",
          "tags": ["Info"],
          "security": [
            "bearerAuth": []
          ],
          "responses": {
            "200": {
              "description": "Translations",
              "content": {
                "application/json": {
                  "schema": {
                    "type": "object",
                    "properties": {
                      "key": {
                        "type": "string"
                      },
                      "value": {
                        "type": "string"
                      }
                    }
                  }
                }
              }
            }
          }
        }
      },
      "/info/settings": {
        "get": {
          "summary": "Settings",
          "description": "Returns the settings of the App",
          "tags": ["Info"],
          "security": [
            "bearerAuth": []
          ],
          "responses": {
            "200": {
              "description": "Settings",
              "content": {
                "application/json": {
                  "schema": {
                    "type": "object",
                    "properties": {
                      "ns": {
                        "type": "object",
                        "properties": {
                          "key": {
                            "type": "string"
                          },
                          "value": {
                            "type": "string"
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      },
      "/info/swagger": {
        "get": {
          "summary": "Swagger",
          "description": "Returns the Swagger",
          "tags": ["Info"],
          "security": [
            "bearerAuth": []
          ],
          "responses": {
            "200": {
              "description": "Swagger",
              "content": {
                "application/json": {
                  "schema": {
                    "type": "object",
                    "properties": {
                      "id": {
                        "type": "integer"
                      },
                      "created_at": {
                        "type": "string",
                        "format": "date-time"
                      },
                      "updated_at": {
                        "type": "string",
                        "format": "date-time"
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    ApplicationRecord.subclasses.each do |d|
      # Only if current user can read the model
      if can? :read, d
        model = d.to_s.underscore.tableize
        pivot["/#{model}"] = {
          "get": {
            "summary": "Index",
            "description": "Returns the list of #{model}",
            "tags": [model.classify],
            "security": [
              "bearerAuth": []
            ],
            "responses": {
              "200": {
                "description": "List of #{model}",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "array",
                      "items": {
                        "type": "object",
                        "properties": create_properties_from_model(d, (d.json_attrs rescue {}))
                      }
                    }
                  }
                }
              },
              "404": {
                "description": "No #{model} found"
              }
            }
          },
          "post": {
            "summary": "Create",
            "description": "Creates a new #{model}",
            "tags": [model.classify],
            "security": [
              "bearerAuth": []
            ],
            "requestBody": {
              "content": {
                "application/json": {
                  "schema": {
                    "type": "object",
                    "properties": {
                      "#{model.singularize}": {
                        "type": "object",
                        "properties": create_properties_from_model(d, (d.json_attrs rescue {}))
                      }
                    }
                  }
                }
              }
            },
            "responses": {
              "200": {
                "description": "#{model} Created",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": create_properties_from_model(d, (d.json_attrs rescue {}))
                    }
                  }
                }
              }
            }
          }
        }
        pivot["/#{model}/search"] = {
          # Complex queries are made using ranskac search via a post endpoint
          "post": {
            "summary": "Search",
            "description": "Searches the #{model} using complex queries. Please refer to the [documentation](https://activerecord-hackery.github.io/ransack/) for the query syntax. In this swagger are presented only some examples, please refer to the complete documentation for more complex queries.\nThe primary method of searching in Ransack is by using what is known as predicates.\nPredicates are used within Ransack search queries to determine what information to match. For instance, the cont predicate will check to see if an attribute called 'name' or 'description' contains a value using a wildcard query.",
            "tags": [model.classify],
            "security": [
              "bearerAuth": []
            ],
            "requestBody": {
              "content": {
                "application/json": {
                  "schema": {
                    "type": "object",
                    "properties": {
                      "q": {
                        "type": "object",
                        "properties": {
                          "name_or_description_cont": {
                            "type": "string"
                          },
                          "first_name_eq": {
                            "type": "string"
                          }
                        }
                      }
                    }
                  }
                }
              }
            },
            "responses": {
              "200": {
                "description": "List of #{model}",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "array",
                      "items": {
                        "type": "object",
                        "properties": create_properties_from_model(d, (d.json_attrs rescue {}))
                      }
                    }
                  }
                }
              },
              "404": {
                "description": "No #{model} found"
              }
            }
          }
        }
        pivot["/#{model}/{id}"] = {
          "put": {
            "summary": "Update",
            "description": "Updates the complete #{model}",
            "parameters": [
              {
                "name": "id",
                "in": "path",
                "required": true,
                "schema": {
                  "type": "integer"
                }
              }
            ],
            "tags": [model.classify],
            "security": [
              "bearerAuth": []
            ],
            "requestBody": {
              "content": {
                "application/json": {
                  "schema": {
                    "type": "object",
                    "properties": {
                      "#{model.singularize}": {
                        "type": "object",
                        "properties": create_properties_from_model(d, {})
                      }
                    }
                  }
                }
              }
            },
            "responses": {
              "200": {
                "description": "#{model} Updated",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": create_properties_from_model(d, (d.json_attrs rescue {}))
                    }
                  }
                }
              },
              "404": {
                "description": "No #{model} found"
              }
            }
          },
          "patch": {
            "summary": "Patch",
            "description": "Updates the partial #{model}",
            "parameters": [
              {
                "name": "id",
                "in": "path",
                "required": true,
                "schema": {
                  "type": "integer"
                }
              }
            ],
            "tags": [model.classify],
            "security": [
              "bearerAuth": []
            ],
            "requestBody": {
              "content": {
                "application/json": {
                  "schema": {
                    "type": "object",
                    "properties": {
                      "#{model.singularize}": {
                        "type": "object",
                        "properties": create_properties_from_model(d, {})
                      }
                    }
                  }
                }
              }
            },
            "responses": {
              "200": {
                "description": "#{model} Patched",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": create_properties_from_model(d, (d.json_attrs rescue {}))
                    }
                  }
                }
              },
              "404": {
                "description": "No #{model} found"
              }
            }
          },
          "delete": {
            "summary": "Delete",
            "description": "Deletes the #{model}",
            "parameters": [
              {
                "name": "id",
                "in": "path",
                "required": true,
                "schema": {
                  "type": "integer"
                }
              }
            ],
            "tags": [model.classify],
            "security": [
              "bearerAuth": []
            ],
            "responses": {
              "200": {
                "description": "#{model} Deleted"
              },
              "404": {
                "description": "No #{model} found"
              }
            }
          },
          "get": {
            "summary": "Show",
            "description": "Shows the #{model}",
            "parameters": [
              {
                "name": "id",
                "in": "path",
                "required": true,
                "schema": {
                  "type": "integer"
                }
              }
            ],
            "tags": [model.classify],
            "security": [
              "bearerAuth": []
            ],
            "responses": {
              "200": {
                "description": "Show #{model}",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": create_properties_from_model(d, (d.json_attrs rescue {}))
                    }
                  }
                }
              },
              "404": {
                "description": "No #{model} found"
              }
            }
          }
        }
        # d.columns_hash.each_pair do |key, val| 
        #   pivot[model][key] = val.type unless key.ends_with? "_id"
        # end
        # # Only application record descendants in order to have a clean schema
        # pivot[model][:associations] ||= {
        #   has_many: d.reflect_on_all_associations(:has_many).map { |a| 
        #     a.name if (((a.options[:class_name].presence || a.name).to_s.classify.constantize.new.is_a? ApplicationRecord) rescue false)
        #   }.compact, 
        #   belongs_to: d.reflect_on_all_associations(:belongs_to).map { |a| 
        #     a.name if (((a.options[:class_name].presence || a.name).to_s.classify.constantize.new.is_a? ApplicationRecord) rescue false)
        #   }.compact
        # }
        # pivot[model][:methods] ||= (d.instance_methods(false).include?(:json_attrs) && !d.json_attrs.blank?) ? d.json_attrs[:methods] : nil
      end
    end
    pivot
  end

  # GET '/api/v2/info/schema'
  def openapi
    uri = URI(request.url)
    pivot = {
      "openapi": "3.0.0",
      "info": {
        "title": "#{Settings.ns(:main).app_name} API",
        "description": "Model Driven Backend [API](https://github.com/gabrieletassoni/thecore/blob/master/docs/04_REST_API.md) created to reflect the actual Active Record Models present in the project in a dynamic way",
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
