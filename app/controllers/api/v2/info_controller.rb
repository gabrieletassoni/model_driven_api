# require 'model_driven_api/version'
class Api::V2::InfoController < Api::V2::ApplicationController
  # Info uses a different auth method: username and password
  skip_before_action :authenticate_request, only: [:version, :swagger, :openapi], raise: false
  skip_before_action :extract_model, except: [:heartbeat, :ntp, :translations], raise: false

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
    render json: current_user.to_json, status: 200
  end

  # api :GET, '/api/v2/info/ntp'
  # Returns the current server time in utc, to check if the client time is synchronized with the server time
  def ntp
    render json: { server_time_utc: Time.current.utc }.to_json, status: 200
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
          has_one: d.reflect_on_all_associations(:has_one).map { |a|
            a.name if (((a.options[:class_name].presence || a.name).to_s.classify.constantize.new.is_a? ApplicationRecord) rescue false)
          }.compact,
          belongs_to: d.reflect_on_all_associations(:belongs_to).map { |a|
            a.name if (((a.options[:class_name].presence || a.name).to_s.classify.constantize.new.is_a? ApplicationRecord) rescue false)
          }.compact,
        }
        pivot[model][:methods] ||= (d.instance_methods(false).include?(:json_attrs) && !d.json_attrs.blank?) ? d.json_attrs[:methods] : nil
      end
    end
    render json: pivot.to_json, status: 200
  end

  def compute_type(model, key)
    Rails.logger.debug "compute_type #{model} #{key}"
    # if it's a file, a date or a text, then return string
    instance = model.new
    # If it's a method, it is a peculiar case, in which we have to return "object" and additionalProperties: true
    return "method" if model.methods.include?(:json_attrs) && model.json_attrs && model.json_attrs.include?(:methods) && model.json_attrs[:methods].include?(key.to_sym)
    # If it's not the case of a method, then it's a field
    method_class = instance.send(key).class.to_s
    Rails.logger.debug "compute_type #{model} #{key} #{method_class}"
    method_key = model.columns_hash[key]

    # Not columns
    return nil if method_key.nil?
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

  def integer?(str)
    true if Integer(str) rescue false
  end

  def number?(str)
    true if Float(str) rescue false
  end

  def datetime?(str)
    true if DateTime.parse(str) rescue false
  end

  def create_properties_from_model(model, dsl, remove_reserved = false)
    parsed_json = JSON.parse(model.new.to_json(dsl))
    parsed_json.keys.map do |k|
      type = compute_type(model, k)

      # Remove fields that cannot be created or updated
      if remove_reserved && %w( id created_at updated_at lock_version ).include?(k.to_s)
        nil
      elsif type == "method" && (parsed_json[k].is_a?(FalseClass) || parsed_json[k].is_a?(TrueClass))
        [k, { "type": "boolean" }]
      elsif type == "method" && parsed_json[k].is_a?(String) && number?(parsed_json[k])
        [k, { "type": "number" }]
      elsif type == "method" && parsed_json[k].is_a?(String) && integer?(parsed_json[k])
        [k, { "type": "integer" }]
      elsif type == "method" && parsed_json[k].is_a?(String) && datetime?(parsed_json[k])
        [k, { "type": "string", "format": "date-time" }]
      elsif type == "method"
        # Unknown or complex format returned
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
      end unless type.blank?
    end.compact.to_h
  end

  def generate_paths
    pivot = {
      "/authenticate": {
        "post": {
          "summary": "Authenticate",
          "tags": ["Authentication"],
          "description": "Authenticate the user and return a JWT token in the header and the current user as body.",
          "security": [
            "basicAuth": [],
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
                          "format": "email",
                        },
                        "password": {
                          "type": "string",
                          "format": "password",
                        },
                      },
                    },
                  },
                  "required": ["email", "password"],
                },
              },
            },
          },
          "responses": {
            "200": {
              "description": "User authenticated",
              "headers": {
                "token": {
                  "description": "JWT",
                  "schema": {
                    "type": "string",
                  },
                },
              },
              "content": {
                "application/json": {
                  "schema": {
                    "type": "object",
                    # ["id", "email", "created_at", "admin", "locked", "supplier_id", "location_id", "roles"]
                    "properties": create_properties_from_model(User, User.json_attrs),
                  },
                },
              },
            },
            "401": {
              "description": "Unauthorized",
            },
          },
        },
      },
      "/raw/sql": {
        "post": {
          "summary": "Raw SQL query execution of SELECT queries",
          "description": "Executes a SQL query on the underlying PostgreSQL database, the query must return the JSON in a **result** key (please note in the examples the _SELECT json_agg(u) AS result_ or in the more complex one the _SELECT jsonb_agg(pick_data) AS result_, they always use the **result** return object).\n \nDesigned for SELECT queries that use the json_agg function to aggregate results into JSON arrays, which must return the JSON in a **result** key.\n \nOther query types are not recommended and may be restricted for security and performance reasons.\n \nOnly SELECT statements are allowed. DDL and DML statements (INSERT, UPDATE, DELETE) are forbidden.\n \nQueries can be as simple as:\n \n```sql\nSELECT json_agg(u) AS result\nFROM users u\nWHERE u.active = true;\n```\n \nor more complex, using joins, subqueries, CTEs, and other SQL features. like:\n \n```sql\nWITH pick_data AS (\n   SELECT p.id,\n      p.project_id,\n      p.quantity,\n      p.created_at,\n      p.updated_at,\n      p.notes,\n      p.document_id,\n      p.external_code,\n      p.reference_project_id,\n      p.reference_row,\n      p.closed,\n      p.parent_reference_row,\n      p.packages,\n      p.weight,\n      p.dispatched_quantity,\n      p.override_item_reference,\n      p.override_item_description,\n      p.override_item_measure_unit,\n      p.lock_version,\n      p.user_id,\n      COALESCE(SUM(pr.quantity), 0) AS quantity_detected,\n      COALESCE(p.quantity, 0) - COALESCE(SUM(pr.quantity), 0) AS quantity_remaining,\n      json_agg(\n         jsonb_build_object(\n            'id',\n            pr.id,\n            'item_id',\n            pr.item_id,\n            'location_id',\n            pr.location_id,\n            'quantity',\n            pr.quantity\n         )\n      ) AS project_rows,\n      jsonb_build_object(\n         'id',\n         l.id,\n         'name',\n         l.name,\n         'description',\n         l.description\n      ) AS location,\n      jsonb_build_object(\n         'id',\n         i.id,\n         'code',\n         i.code,\n         'created_at',\n         i.created_at,\n         'updated_at',\n         i.updated_at,\n         'description',\n         i.description,\n         'has_serials',\n         i.has_serials,\n         'external_code',\n         i.external_code,\n         'barcode',\n         i.barcode,\n         'weight',\n         i.weight,\n         'quantity',\n         i.quantity,\n         'package_quantity',\n         i.package_quantity,\n         'locked_quantity',\n         i.locked_quantity,\n         'disabled',\n         i.disabled,\n         'measure_unit',\n         jsonb_build_object('id', mu.id, 'name', mu.name),\n         'location',\n         jsonb_build_object('id', il.id, 'name', il.name),\n         'locations',\n         (\n            SELECT jsonb_agg(\n                  jsonb_build_object('id', loc.id, 'name', loc.name)\n               )\n            FROM locations loc\n               JOIN item_locations il ON il.location_id = loc.id\n            WHERE il.item_id = i.id\n         ),\n         'additional_barcodes',\n         (\n            SELECT jsonb_agg(\n                  jsonb_build_object('id', ab.id, 'code', ab.code)\n               )\n            FROM additional_barcodes ab\n            WHERE ab.item_id = i.id\n         )\n      ) AS item\n   FROM picks p\n      LEFT JOIN project_rows pr ON pr.pick_id = p.id\n      LEFT JOIN locations l ON l.id = p.location_id\n      LEFT JOIN items i ON i.id = p.item_id\n      LEFT JOIN measure_units mu ON mu.id = i.measure_unit_id\n      LEFT JOIN locations il ON il.id = i.location_id\n   WHERE p.project_id = 16130\n   GROUP BY p.id,\n      l.id,\n      i.id,\n      mu.id,\n      il.id\n)\nSELECT jsonb_agg(pick_data) AS result\nFROM pick_data;\n```\n \nLet's break down the provided SQL query and understand why it uses a Common Table Expression (CTE) and how it can improve performance.\n \n### Explanation of the complex Query\n \nThe provided query uses a CTE named `pick_data` to gather and aggregate data from multiple tables (`picks`, `project_rows`, `locations`, `items`, `measure_units`, `item_locations`, and `additional_barcodes`). The final result is a JSON array of aggregated data.\n \n#### Key Components of the Query:\n \n1. **CTE Definition**:\n \n   ```sql\n   WITH pick_data AS (\n     -- Subquery content\n   )\n   ```\n \n   The CTE `pick_data` is defined to encapsulate the logic of the subquery. This makes the query more readable and modular.\n \n2. **Data Selection and Aggregation**:\n   Inside the CTE, data is selected and aggregated from various tables. Key operations include:\n \n   - **Column Selection**: Selecting specific columns from the `picks` table.\n   - **Aggregation**: Using `COALESCE` and `SUM` to calculate `quantity_detected` and `quantity_remaining`.\n   - **JSON Aggregation**: Using `json_agg` and `jsonb_build_object` to create JSON objects and arrays for nested data structures.\n \n3. **Final Selection**:\n   ```sql\n   SELECT jsonb_agg(pick_data) AS result FROM pick_data;\n   ```\n   The final selection aggregates all rows from the CTE `pick_data` into a single JSON array.\n \n### Why Use a CTE?\n \n1. **Readability and Maintainability**:\n \n   - **Modular Code**: By using a CTE, the complex logic is encapsulated in a named subquery, making the main query easier to read and understand.\n   - **Reusability**: The CTE can be reused within the same query if needed, avoiding duplication of code.\n \n2. **Performance**:\n   - **Optimization**: Modern SQL engines can optimize CTEs effectively. They can be materialized (computed once and stored) or inlined (expanded in the main query) based on the query plan.\n   - **Intermediate Results**: CTEs allow breaking down complex queries into simpler steps, which can sometimes help the SQL engine optimize each step more effectively.\n \n### Documentation for Editing Generic Queries\n \nWhen editing or creating new queries, consider the following steps and best practices:\n \n1. **Identify the Purpose**:\n \n   - Clearly define what the query needs to achieve. Understand the data relationships and the final output format.\n \n2. **Use CTEs for Complex Logic**:\n \n   - Break down complex queries into smaller, manageable parts using CTEs. This improves readability and maintainability.\n \n3. **Optimize Aggregations and Joins**:\n \n   - Ensure that aggregations and joins are optimized. Use indexes where appropriate and avoid unnecessary computations.\n \n4. **Leverage JSON Functions**:\n \n   - Use JSON functions (`json_agg`, `jsonb_build_object`, etc.) to handle nested data structures effectively.\n \n5. **Test and Validate**:\n   - Test the query with different datasets to ensure it performs well and returns the correct results. Validate the output format.\n \n### Example of a Generic Query Using CTE\n \nHere's a generic example to illustrate how to use a CTE in a query:\n \n```sql\n \n\nWITH data_aggregation AS (\n  SELECT\n    t1.id,\n    t1.name,\n    SUM(t2.value) AS total_value,\n    json_agg(\n      jsonb_build_object(\n        'id', t2.id,\n        'value', t2.value\n      )\n    ) AS details\n  FROM table1 t1\n  LEFT JOIN table2 t2 ON t2.table1_id = t1.id\n  GROUP BY t1.id\n)\nSELECT jsonb_agg(data_aggregation) AS result FROM data_aggregation;\n```\n \n### Conclusion\n \nUsing CTEs in SQL queries helps in organizing complex logic, improving readability, and potentially enhancing performance. When editing or creating new queries, follow best practices such as breaking down complex logic, optimizing joins and aggregations, and leveraging JSON functions for nested data structures.\n",
          "tags": ["Raw"],
          "security": [
            "bearerAuth": [],
          ],
          "responses": {
            "200": {
              "description": "SQL Query Result",
              "content": {
                "application/json": {
                  "schema": {
                    "type": "array",
                    "items": {
                      "type": "object",
                      "properties": {
                        "json_agg": {
                          "type": "string",
                        },
                      },
                    },
                  },
                },
              },
            },
            "400": {
              "description": "SQL query must return a key called result otherwise cannot be parsed",
              "content": {
                "application/json": {
                  "schema": {
                    "type": "object",
                    "properties": {
                      "error": {
                        "type": "string",
                      },
                    },
                  },
                },
              },
            },

          },
          "requestBody": {
            "content": {
              "application/json": {
                "schema": {
                  "type": "object",
                  "properties": {
                    "query": {
                      "type": "string",
                      "example": "SELECT json_agg(u) FROM users u WHERE u.active = true;",
                    },
                  },
                },
              },
            },
          },
        },
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
                    "type": "string",
                  },
                },
              },
            },
          },
        },
      },
      "/info/heartbeat": {
        "get": {
          "summary": "Heartbeat",
          "description": "Just keeps the session alive by returning a new token",
          "tags": ["Info"],
          "security": [
            "bearerAuth": [],
          ],
          "responses": {
            "200": {
              "description": "Session alive",
              "headers": {
                "token": {
                  "description": "JWT",
                  "schema": {
                    "type": "string",
                  },
                },
              },
            },
          },
        },
      },
      "/info/roles": {
        "get": {
          "summary": "Roles",
          "description": "Returns the roles list",
          "tags": ["Info"],
          "security": [
            "bearerAuth": [],
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
                          "type": "integer",
                        },
                        "name": {
                          "type": "string",
                        },
                        "description": {
                          "type": "string",
                        },
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
      "/info/schema": {
        "get": {
          "summary": "Schema",
          "description": "Returns the schema of the models",
          "tags": ["Info"],
          "security": [
            "bearerAuth": [],
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
                          "type": "integer",
                        },
                        "created_at": {
                          "type": "string",
                          "format": "date-time",
                        },
                        "updated_at": {
                          "type": "string",
                          "format": "date-time",
                        },
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
      "/info/dsl": {
        "get": {
          "summary": "DSL",
          "description": "Returns the DSL of the models",
          "tags": ["Info"],
          "security": [
            "bearerAuth": [],
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
                        "type": "integer",
                      },
                      "created_at": {
                        "type": "string",
                        "format": "date-time",
                      },
                      "updated_at": {
                        "type": "string",
                        "format": "date-time",
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
      "/info/translations": {
        "get": {
          "summary": "Translations",
          "description": "Returns the translations of the entire App",
          "tags": ["Info"],
          "security": [
            "bearerAuth": [],
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
                        "type": "string",
                      },
                      "value": {
                        "type": "string",
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
      "/info/settings": {
        "get": {
          "summary": "Settings",
          "description": "Returns the settings of the App",
          "tags": ["Info"],
          "security": [
            "bearerAuth": [],
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
                            "type": "string",
                          },
                          "value": {
                            "type": "string",
                          },
                        },
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
      "/info/swagger": {
        "get": {
          "summary": "Swagger",
          "description": "Returns the self generated Swagger for all the models in the App.",
          "tags": ["Info"],
          "responses": {
            "200": {
              "description": "Swagger",
              "content": {
                "application/json": {
                  "schema": {
                    "type": "object",
                    "properties": {
                      "id": {
                        "type": "integer",
                      },
                      "created_at": {
                        "type": "string",
                        "format": "date-time",
                      },
                      "updated_at": {
                        "type": "string",
                        "format": "date-time",
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
    }
    ApplicationRecord.subclasses.sort_by { |d| d.to_s }.each do |d|
      # Only if current user can read the model
      if true # can? :read, d
        model = d.to_s.underscore.tableize
        # CRUD and Search endpoints
        pivot["/#{model}"] = {
          "get": {
            "summary": "Index",
            "description": "Returns the list of #{model}",
            "tags": [model.classify],
            "security": [
              "bearerAuth": [],
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
                        "properties": create_properties_from_model(d, (d.json_attrs rescue {})),
                      },
                    },
                  },
                },
              },
              "404": {
                "description": "No #{model} found",
              },
            },
          },
          "post": {
            "summary": "Create",
            "description": "Creates a new #{model}",
            "tags": [model.classify],
            "security": [
              "bearerAuth": [],
            ],
            "requestBody": {
              "content": {
                "application/json": {
                  "schema": {
                    "type": "object",
                    "properties": {
                      "#{model.singularize}": {
                        "type": "object",
                        "properties": create_properties_from_model(d, {}, true),
                      },
                    },
                  },
                },
              },
            },
            "responses": {
              "200": {
                "description": "#{model} Created",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": create_properties_from_model(d, (d.json_attrs rescue {})),
                    },
                  },
                },
              },
            },
          },
        }
        # Non CRUD or Search, but custom, usually bulk operations endpoints
        new_custom_actions = ("Endpoints::#{d.model_name.name}".constantize.instance_methods(false) rescue [])
        Rails.logger.debug "New Custom Actions (#{d.model_name.name}): #{new_custom_actions}"
        new_custom_actions.each do |action|
          openapi_definition = "Endpoints::#{d.model_name.name}".constantize.definitions[d.model_name.name][action.to_sym] rescue []

          # Add the tag to the openapi definition
          openapi_definition.each do |k, v|
            v[:tags] = [d.model_name.name]
          end

          pivot["/#{model}/custom_action/#{action}"] = openapi_definition if openapi_definition
        end
        pivot["/#{model}/search"] = {
          # Complex queries are made using ranskac search via a post endpoint
          "post": {
            "summary": "Search",
            "description": "Searches the #{model} using complex queries. Please refer to the [documentation](https://activerecord-hackery.github.io/ransack/) for the query syntax and to the general description of this swagger document to discover the usage of other, non ransack predicates for example to count records, select only some fields and more.",
            "tags": [model.classify],
            "security": [
              "bearerAuth": [],
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
                            "type": "string",
                          },
                          "first_name_eq": {
                            "type": "string",
                          },
                        },
                      },
                    },
                  },
                },
              },
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
                        "properties": create_properties_from_model(d, (d.json_attrs rescue {})),
                      },
                    },
                  },
                },
              },
              "404": {
                "description": "No #{model} found",
              },
            },
          },
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
                  "type": "integer",
                },
              },
            ],
            "tags": [model.classify],
            "security": [
              "bearerAuth": [],
            ],
            "requestBody": {
              "content": {
                "application/json": {
                  "schema": {
                    "type": "object",
                    "properties": {
                      "#{model.singularize}": {
                        "type": "object",
                        "properties": create_properties_from_model(d, {}, true),
                      },
                    },
                  },
                },
              },
            },
            "responses": {
              "200": {
                "description": "#{model} Updated",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": create_properties_from_model(d, (d.json_attrs rescue {})),
                    },
                  },
                },
              },
              "404": {
                "description": "No #{model} found",
              },
            },
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
                  "type": "integer",
                },
              },
            ],
            "tags": [model.classify],
            "security": [
              "bearerAuth": [],
            ],
            "requestBody": {
              "content": {
                "application/json": {
                  "schema": {
                    "type": "object",
                    "properties": {
                      "#{model.singularize}": {
                        "type": "object",
                        "properties": create_properties_from_model(d, {}, true),
                      },
                    },
                  },
                },
              },
            },
            "responses": {
              "200": {
                "description": "#{model} Patched",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": create_properties_from_model(d, (d.json_attrs rescue {})),
                    },
                  },
                },
              },
              "404": {
                "description": "No #{model} found",
              },
            },
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
                  "type": "integer",
                },
              },
            ],
            "tags": [model.classify],
            "security": [
              "bearerAuth": [],
            ],
            "responses": {
              "200": {
                "description": "#{model} Deleted",
              },
              "404": {
                "description": "No #{model} found",
              },
            },
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
                  "type": "integer",
                },
              },
            ],
            "tags": [model.classify],
            "security": [
              "bearerAuth": [],
            ],
            "responses": {
              "200": {
                "description": "Show #{model}",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": create_properties_from_model(d, (d.json_attrs rescue {})),
                    },
                  },
                },
              },
              "404": {
                "description": "No #{model} found",
              },
            },
          },
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

  def info_description
    info = <<-MARKDOWN

## About this API Documentation

Model Driven Backend [API](https://github.com/gabrieletassoni/thecore/blob/master/docs/04_REST_API.md) created to reflect the actual Active Record Models present in the project in a dynamic way.

This swagger describes all the CRUD endpoints provided by the application, as well as all the custom endpoints and gives a deep dive into the parameters accepted in GET (Index) requests and POST (Search) requests. Since the controller unifies params (via request.parameters), the filtering logic is identical whether parameters are passed in the Query String (GET) or the JSON Body (POST).

The documentation starts from the authentication mechanism, integrated with the details from the provided code.
Here is the updated and integrated documentation for the Authentication mechanism. It now covers the full lifecycle: obtaining the initial token via the login endpoint and maintaining the session via the sliding expiration mechanism found in the controller.

---

## Authentication & Token Management

The API implements a **stateless JWT (JSON Web Token)** authentication mechanism. It consists of two distinct phases:

1. **Initial Authentication:** Exchanging credentials for the first Token.
2. **Session Maintenance:** Using a **Sliding Expiration** strategy where every subsequent successful request issues a fresh token.

### 1. Initial Authentication (Login)

To begin a session, the client must POST user credentials to the authentication endpoint. This is the only request that does not require an `Authorization` header.

#### Request

**Endpoint:** `POST /api/v2/authenticate`

**Body:**

```json
{
    "auth": {
        "email": "admin@example.com",
        "password": "Change#1"
    }
}

```

#### Response

Upon successful authentication, the server returns two critical pieces of data:

1. **Response Body:** Contains the User object details.
2. **Response Headers:** Contains the initial JWT in the `token` header.

**Example Body:**

```json
{
    "id": 219,
    "email": "admin@example.com",
    "created_at": "2025-12-10T07:57:54.336Z",
    "admin": true,
    "locked": false,
    "locale": "en",
    // ... other user attributes
    "roles": []
}

```

**Example Headers:**
Note the presence of the `token` header.

```http
HTTP/1.1 200 OK
content-type: application/json; charset=utf-8
token: eyJhbGciOiJIUzI1NiJ9.eyJ1c2VyX2lkIjoyMTksImV4cCI6MTc2NjQ3ODMwN30.I0qJzOwA0Jxx0frL5-9jVH2PsakdZjSEY8Kqb9S3GKo
x-request-id: 113cad63-11f8-4daf-b684-19322a053bcc
...

```

---

### 2. Sliding Expiration (Token Renewal)

Once the client has the initial token, the `Api::V2::ApplicationController` handles the lifecycle. Instead of a fixed expiration time that forces a re-login, the API issues a **brand new token** with every successfully authenticated request.

#### The Renewal Mechanism

1. **Client Request:** The client sends the *current* token in the `Authorization` header.
```http
Authorization: Bearer <Current_Token>

```


2. **Verification:** The `authenticate_request` method verifies the token. If valid, it sets `@current_user`.
3. **Renewal:** Before sending the response, the controller generates a new JWT encoded with the current user's ID and sets it in the response header.
```ruby
response.set_header("Token", JsonWebToken.encode(user_id: current_user.id))

```

#### Client-Side Implementation Guide

To maintain a valid session, the client must implement an interceptor to handle token rotation:

1. **Login:** Call `/api/v2/authenticate` and store the `token` from the response header.
2. **Subsequent Requests:** Attach the stored token to the `Authorization: Bearer ...` header.
3. **Update Storage:**
* Check every response for a `Token` header.
* **If present:** Immediately replace the stored token with this new value.
* **If missing:** Continue using the existing token (unless the response was a 401/403 error).

#### Failure Scenarios

If the `authenticate_request` fails (e.g., token expired, invalid signature):

* The controller returns an unauthenticated error (`unauthenticated!`).
* The execution halts, and the line generating the new header is never reached.
* **Result:** The client receives a 401 error and **no new token**, signaling that the user must perform the **Initial Authentication** (login) again.

---

## API Documentation: Search, Filtering, and Pagination Parameters

### 1. Pagination and Counting

These parameters control the amount of data returned and navigation through result pages.

* **`page`** (Integer): Indicates the page number to retrieve. If omitted, pagination is not applied (or defaults to the model's Kaminari configuration).
* **`per`** (Integer): Indicates the number of records per page. Works in conjunction with `page`.
* **`count`** (Boolean/Any value): If present and not empty, the API **does not** return the list of records but a JSON object containing only the total count of records matching the search criteria (e.g., `{ "count": 42 }`). Useful for displaying total results before loading them.

### 2. Field Selection

It is possible to limit the fields returned in the JSON response or include associations. The controller looks for these parameters in `a` or `json_attrs`.

* **`a`** (or `json_attrs`): An object or hash defining the output JSON structure.
* **`only`**: Array of strings. Returns only the specified attributes of the main model.
* **`methods`**: Array of strings. Includes model methods that are not database columns.
* **`include`**: Object for including relationships (associations). Associations can also have their own `only` or `methods`.

### 3. Custom Actions

* **`do`**: Specifies a custom action (`custom_action`) to execute on the model instead of the standard `index`.
* Format: `?do=action_name` or `?do=action_name-token`.
* The controller will look for a class method `custom_action_action_name` or a module `Endpoints::Model`.

### 4. Filters and Sorting (Ransack)

The core of the search functionality lies in the **`q`** parameter. The controller implements the **Ransack** gem, allowing for complex queries, filtering on associations, and dynamic sorting.

Basic structure: `q[field_name_predicate]=value`

#### Common Predicates (Suffixes)

* `_eq`: Equal to (e.g., `status_eq`).
* `_cont`: Contains (LIKE %value%, case insensitive).
* `_start`: Starts with.
* `_end`: Ends with.
* `_gt` / `_lt`: Greater than / Less than (for numbers or dates).
* `_gteq` / `_lteq`: Greater than or equal to / Less than or equal to.
* `_in`: Included in a list (accepts an array).
* `_present`: If set to `1` or `true`, filters for non-null values. `_blank` for nulls.

#### Sorting

* `s`: Defines the sorting order. Format: `field_name asc` or `field_name desc`.

---

## Practical Examples

Below are two usage scenarios to achieve the same result: a **GET** request (URL parameters) and a **POST** request (JSON Body parameters).

#### Scenario A: Simple Search and Pagination

**Goal:** Find users whose name contains "Mario", paginated (page 2, 10 per page).

##### 1. Using GET (Query String)

Parameters are "flattened" and encoded in the URL.

```text
GET /api/v2/users?q[name_cont]=Mario&page=2&per=10

```

##### 2. Using POST (JSON Body)

Ideal for complex searches to avoid exceeding URL length limits.

```json
POST /api/v2/users/search
Content-Type: application/json

{
  "q": {
    "name_cont": "Mario"
  },
  "page": 2,
  "per": 10
}

```

---

#### Scenario B: Advanced Search, Sorting, and Field Selection

**Goal:**

1. Search for orders (`orders`) where `total_price` is greater than 50.
2. Belonging to a user (`user`) whose email ends with `@test.com`.
3. Sort by creation date descending.
4. Return only the `id` and `total_price` of the order, including the `email` of the associated user.

##### 1. Using GET (Query String)

Note the square bracket syntax for nested structures (`q`, `a`).

```text
GET /api/v2/orders?q[total_price_gt]=50&q[user_email_end]=@test.com&q[s]=created_at desc&a[only][]=id&a[only][]=total_price&a[include][user][only][]=email

```

##### 2. Using POST (JSON Body)

Much more readable for nested structures like `a` (json_attrs).

```json
POST /api/v2/orders/search
Content-Type: application/json

{
  "q": {
    "total_price_gt": 50,
    "user_email_end": "@test.com",
    "s": "created_at desc"
  },
  "a": {
    "only": ["id", "total_price"],
    "include": {
      "user": {
        "only": ["email"]
      }
    }
  }
}

```

---

#### Scenario C: Multiple Search (OR) and Arrays

**Goal:** Find products where status is "new" **OR** "refurbished" (using `_in`).

##### 1. Using GET (Query String)

To pass an array in GET, repeat the empty square brackets `[]`.

```text
GET /api/v2/products?q[status_in][]=new&q[status_in][]=refurbished

```

##### 2. Using POST (JSON Body)

```json
POST /api/v2/products/search
Content-Type: application/json

{
  "q": {
    "status_in": ["new", "refurbished"]
  }
}

```

---

#### Scenario D: Count Only

**Goal:** Know how many users are active without downloading the data.

##### 1. Using GET

```text
GET /api/v2/users?q[active_eq]=true&count=true

```

##### 2. Using POST

```json
POST /api/v2/users/search
Content-Type: application/json

{
  "q": {
    "active_eq": true
  },
  "count": true
}

```

**Expected Response:**

```json
{
  "count": 156
}

```

## ActiveStorage Integration: React Frontend & Rails Backend

### Overview

This guide explains how to handle file uploads (via Camera or Gallery) and attachment deletions using a **React** frontend and a **Ruby on Rails** backend.

The Rails model uses a virtual attribute strategy for deletion:

* **Upload:** handled via `has_many_attached :assets`
* **Deletion:** handled via `attr_accessor :remove_assets`

---

### 1. Handling File Objects (No "Paths" needed)

In a web/mobile context (React Web or PWA), you do not need a file system path. When a user takes a photo or selects a file, the browser creates a native **`File`** object (a type of `Blob`).

You must send this binary object to the backend using **`FormData`**.

#### React Component Example

This component handles:

1. **File Input:** Supports both gallery selection and direct camera capture on mobile.
2. **FormData:** Constructs the payload correctly for Rails.
3. **API Call:** Sends the data via `fetch`.

```jsx
import React, { useState } from 'react';

const ProductForm = () => {
  const [title, setTitle] = useState('');
  const [selectedFiles, setSelectedFiles] = useState([]);

  // Handle file selection
  const handleFileChange = (event) => {
    // event.target.files is a FileList; convert to Array for convenience
    const filesArray = Array.from(event.target.files);
    setSelectedFiles(filesArray);
  };

  // Handle form submission
  const handleSubmit = async (event) => {
    event.preventDefault();

    // 1. Create the FormData object
    const formData = new FormData();

    // 2. Append text fields
    formData.append('product[title]', title);

    // 3. Append FILES
    // It is crucial to use 'product[assets][]' with brackets.
    // This tells Rails to treat it as an array of attachments.
    selectedFiles.forEach((file) => {
      formData.append('product[assets][]', file);
    });

    try {
      const response = await fetch('http://localhost:3000/api/products', {
        method: 'POST',
        // IMPORTANT NOTE:
        // When using FormData, do NOT set 'Content-Type': 'application/json'
        // and do NOT manually set 'multipart/form-data'.
        // The browser will automatically set the header with the correct 'boundary'.
        body: formData,
      });

      if (response.ok) {
        console.log("Upload successful!");
        // Reset form or redirect...
      } else {
        console.error("Upload error");
      }
    } catch (error) {
      console.error("Network error:", error);
    }
  };

  return (
    <form onSubmit={handleSubmit} style={{ padding: '20px' }}>
      <div>
        <label>Product Title:</label>
        <input 
          type="text" 
          value={title} 
          onChange={(e) => setTitle(e.target.value)} 
        />
      </div>

      <div style={{ marginTop: '20px' }}>
        <label>Photos (Camera or Gallery):</label>
        {/* accept="image/*": Accepts only images.
           capture="environment": On mobile, opens the rear camera directly.
           Remove 'capture' if you want the user to choose between Gallery and Camera.
           multiple: Allows selecting multiple photos.
        */}
        <input 
          type="file" 
          accept="image/*" 
          multiple
          onChange={handleFileChange} 
        />
      </div>

      <button type="submit" style={{ marginTop: '20px' }}>
        Save Product
      </button>
    </form>
  );
};

export default ProductForm;

```

---

### 2. Key Implementation Details

#### A. The `capture` Attribute

* `<input type="file" capture="environment" />`: Opens the **rear camera** directly on iOS/Android.
* `<input type="file" capture="user" />`: Opens the **front camera** (selfie mode).
* **No `capture` attribute** (but with `accept="image/*"`): The device will prompt the user: *"Take Photo or Photo Library?"*. This is often the best UX.

#### B. The `forEach` Loop

You cannot pass an array directly into `FormData` (e.g., `formData.append('key', myArray)` will not work).
Rails expects multiple values for the same key. You must append each file individually:

```javascript
// Correct
files.forEach(file => formData.append('product[assets][]', file));

```

#### C. The Content-Type Header

This is a common pitfall. When using `fetch` or `axios` with a `FormData` body, **do not set the Content-Type header manually**.
The browser must generate it automatically to include the boundary:
`Content-Type: multipart/form-data; boundary=----WebKitFormBoundary...`

---

## 3. Handling Deletion (PATCH Request)

To remove specific attachments using the `remove_assets` virtual attribute defined in your Rails model, send the **Attachment IDs** (not the file objects).

```javascript
const handleUpdate = async () => {
  const formData = new FormData();
  
  // 1. Add new files (if any)
  newFiles.forEach(file => formData.append('product[assets][]', file));

  // 2. Add IDs to remove 
  // (e.g., idsToRemove is an array like [12, 45])
  idsToRemove.forEach(id => formData.append('product[remove_assets][]', id));

  await fetch(`http://localhost:3000/api/products/${productId}`, {
    method: 'PATCH',
    body: formData
  });
};

```

### 4. Bare Metal HTTP Requests

If you were to inspect the network traffic or manually construct the request (e.g., using raw sockets or a tool like Postman/Insomnia), this is exactly what the payload looks like "over the wire."

#### A. POST Request (Upload)

Notice how `multipart/form-data` uses a **boundary** string (randomly generated by the client) to separate different fields.

```http
POST /api/products HTTP/1.1
Host: localhost:3000
Content-Type: multipart/form-data; boundary=----WebKitFormBoundary7MA4YWxkTrZu0gW

------WebKitFormBoundary7MA4YWxkTrZu0gW
Content-Disposition: form-data; name="product[title]"

My New Product
------WebKitFormBoundary7MA4YWxkTrZu0gW
Content-Disposition: form-data; name="product[assets][]"; filename="camera_shot.jpg"
Content-Type: image/jpeg

(Binary image data goes here...)
------WebKitFormBoundary7MA4YWxkTrZu0gW
Content-Disposition: form-data; name="product[assets][]"; filename="gallery_photo.png"
Content-Type: image/png

(Binary image data goes here...)
------WebKitFormBoundary7MA4YWxkTrZu0gW--

```

#### B. PATCH Request (Deletion via IDs)

When sending the `remove_assets` array via `FormData`, the key is repeated for every ID. This is how HTTP handles arrays in form data.

```http
PATCH /api/products/100 HTTP/1.1
Host: localhost:3000
Content-Type: multipart/form-data; boundary=----WebKitFormBoundaryXyZ123

------WebKitFormBoundaryXyZ123
Content-Disposition: form-data; name="product[remove_assets][]"

12
------WebKitFormBoundaryXyZ123
Content-Disposition: form-data; name="product[remove_assets][]"

45
------WebKitFormBoundaryXyZ123--

```
    MARKDOWN
    info
  end

  # GET '/api/v2/info/schema'
  def openapi
    uri = URI(request.url)
    pivot = {
      "openapi": "3.0.0",
      "info": {
        "title": "#{Settings.ns(:main).app_name} API",
        "description": info_description,
        "version": "v2",
      },
      "servers": [
        {
          # i.e. "http://localhost:3001/api/v2"
          "url": "#{uri.scheme}://#{uri.host}#{":#{uri.port}" if uri.port.present?}/api/v2",
          "description": "The URL at which this API responds.",
        },
      ],
      # 1) Define the security scheme type (HTTP bearer)
      "components": {
        "securitySchemes": {
          "basicAuth": {
            "type": "http",
            "scheme": "basic",
          },
          "bearerAuth": { # arbitrary name for the security scheme
            "type": "http",
            "scheme": "bearer",
            "bearerFormat": "JWT", # optional, arbitrary value for documentation purposes
          },
        },
      },
      # 2) Apply the security globally to all operations
      "security": [
        {
          "bearerAuth": [], # use the same name as above
        },
      ],
      "paths": generate_paths,
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
    render json: ThecoreSettings::Setting.pluck(:ns, :key, :raw).inject({}) { |result, array| (result[array.first] ||= {})[array.second] = array.third; result }.to_json, status: 200
  end
end
