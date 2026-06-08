module Api
  module OpenApi
    class V3 < Base
      def generate
        paths = {}
        paths.merge!(v3_authenticate_path)
        paths.merge!(v3_raw_sql_paths)
        paths.merge!(v3_info_paths)
        ApplicationRecord.subclasses.sort_by(&:to_s).each do |model_class|
          paths.merge!(v3_crud_paths(model_class))
          paths.merge!(v3_custom_action_paths(model_class))
        end
        paths
      end

      def description
        v3_description
      end

      private

      def v3_authenticate_path
        {
          "/authenticate" => {
            "post" => {
              "summary" => "Authenticate",
              "tags" => ["Authentication"],
              "description" => "Exchange email/password for a JWT. The token is returned in the `Token` response header.",
              "requestBody" => {
                "required" => true,
                "content" => {
                  "application/json" => {
                    "schema" => {
                      "type" => "object",
                      "properties" => {
                        "auth" => {
                          "type" => "object",
                          "properties" => {
                            "email" => { "type" => "string", "format" => "email" },
                            "password" => { "type" => "string", "format" => "password" },
                          },
                        },
                      },
                    },
                  },
                },
              },
              "responses" => {
                "200" => {
                  "description" => "Authenticated — JWT in Token header",
                  "headers" => { "Token" => { "description" => "JWT", "schema" => { "type" => "string" } } },
                },
                "401" => { "description" => "Unauthorized" },
              },
            },
          },
        }
      end

      def v3_raw_sql_paths
        response_schema = {
          "type" => "array",
          "items" => { "type" => "object", "additionalProperties" => true },
        }
        query_param = {
          "name" => "query",
          "in" => "query",
          "required" => true,
          "schema" => { "type" => "string" },
          "example" => "SELECT id, name FROM roles LIMIT 10",
        }
        body_schema = {
          "type" => "object",
          "properties" => { "query" => { "type" => "string" } },
        }
        {
          "/raw/sql" => {
            "get" => {
              "summary" => "Raw SQL (GET)",
              "tags" => ["Raw"],
              "description" => "Execute a SELECT query. Returns rows as a plain JSON array (not JSON:API).",
              "security" => [{ "bearerAuth" => [] }],
              "parameters" => [query_param],
              "responses" => {
                "200" => { "description" => "Rows", "content" => { "application/json" => { "schema" => response_schema } } },
                "400" => { "description" => "Only SELECT statements are allowed" },
              },
            },
            "post" => {
              "summary" => "Raw SQL (POST)",
              "tags" => ["Raw"],
              "description" => "Execute a SELECT query. Returns rows as a plain JSON array (not JSON:API).",
              "security" => [{ "bearerAuth" => [] }],
              "requestBody" => { "required" => true, "content" => { "application/json" => { "schema" => body_schema } } },
              "responses" => {
                "200" => { "description" => "Rows", "content" => { "application/json" => { "schema" => response_schema } } },
                "400" => { "description" => "Only SELECT statements are allowed" },
              },
            },
          },
        }
      end

      def v3_info_paths
        {
          "/info/version" => {
            "get" => {
              "summary" => "Version", "tags" => ["Info"],
              "responses" => { "200" => { "description" => "App version string" } },
            },
          },
          "/info/heartbeat" => {
            "get" => {
              "summary" => "Heartbeat", "tags" => ["Info"],
              "security" => [{ "bearerAuth" => [] }],
              "responses" => { "200" => { "description" => "Renews token, returns current user as plain JSON" } },
            },
          },
          "/info/roles" => {
            "get" => {
              "summary" => "Roles", "tags" => ["Info"],
              "security" => [{ "bearerAuth" => [] }],
              "responses" => { "200" => { "description" => "All roles as plain JSON array" } },
            },
          },
          "/info/schema" => {
            "get" => {
              "summary" => "Schema", "tags" => ["Info"],
              "security" => [{ "bearerAuth" => [] }],
              "responses" => { "200" => { "description" => "DB schema for models the user can read" } },
            },
          },
          "/info/dsl" => {
            "get" => {
              "summary" => "DSL", "tags" => ["Info"],
              "security" => [{ "bearerAuth" => [] }],
              "responses" => { "200" => { "description" => "json_attrs DSL for each model" } },
            },
          },
          "/info/translations" => {
            "get" => {
              "summary" => "Translations", "tags" => ["Info"],
              "security" => [{ "bearerAuth" => [] }],
              "parameters" => [{ "name" => "locale", "in" => "query", "schema" => { "type" => "string" } }],
              "responses" => { "200" => { "description" => "Full i18n translation tree" } },
            },
          },
          "/info/settings" => {
            "get" => {
              "summary" => "Settings", "tags" => ["Info"],
              "security" => [{ "bearerAuth" => [] }],
              "responses" => { "200" => { "description" => "All ThecoreSettings::Setting values" } },
            },
          },
          "/info/swagger" => {
            "get" => {
              "summary" => "OpenAPI v3 spec", "tags" => ["Info"],
              "responses" => { "200" => { "description" => "This OpenAPI 3.0 specification" } },
            },
          },
        }
      end

      def v3_crud_paths(model_class)
        resource_type = model_class.model_name.plural
        tag = model_class.model_name.name

        attrs = begin
          props = create_properties_from_model(model_class, model_class.json_attrs || {})
          props.reject { |k, _| k.to_s == "id" }
        rescue
          {}
        end

        writable_attrs = begin
          create_properties_from_model(model_class, {}, true)
        rescue
          {}
        end

        resource_schema = {
          "type" => "object",
          "properties" => {
            "id" => { "type" => "string" },
            "type" => { "type" => "string", "example" => resource_type },
            "attributes" => { "type" => "object", "properties" => attrs },
          },
        }
        collection_schema = {
          "type" => "object",
          "properties" => {
            "data" => { "type" => "array", "items" => resource_schema },
            "meta" => { "type" => "object", "properties" => { "total" => { "type" => "integer" } } },
          },
        }
        single_schema = { "type" => "object", "properties" => { "data" => resource_schema } }
        request_schema = {
          "type" => "object",
          "properties" => {
            "data" => {
              "type" => "object",
              "properties" => {
                "type" => { "type" => "string", "example" => resource_type },
                "attributes" => { "type" => "object", "properties" => writable_attrs },
              },
            },
          },
        }

        filter_params = begin
          model_class.ransackable_attributes.map do |attr|
            { "name" => "filter[#{attr}]", "in" => "query", "schema" => { "type" => "string" } }
          end
        rescue
          []
        end

        id_param = { "name" => "id", "in" => "path", "required" => true, "schema" => { "type" => "integer" } }
        sort_param = { "name" => "sort", "in" => "query", "schema" => { "type" => "string" }, "description" => "field or -field (descending), comma-separated" }
        page_params = [
          { "name" => "page[number]", "in" => "query", "schema" => { "type" => "integer" } },
          { "name" => "page[size]",   "in" => "query", "schema" => { "type" => "integer" } },
        ]
        include_param  = { "name" => "include", "in" => "query", "schema" => { "type" => "string" }, "description" => "Associations to sideload (empty to suppress defaults)" }
        fields_param   = { "name" => "fields[#{resource_type}]", "in" => "query", "schema" => { "type" => "string" }, "description" => "Sparse fieldsets" }

        vnd = "application/vnd.api+json"

        {
          "/#{resource_type}" => {
            "get" => {
              "summary" => "Index #{tag}",
              "tags" => [tag],
              "security" => [{ "bearerAuth" => [] }],
              "parameters" => [*page_params, *filter_params, sort_param, include_param, fields_param],
              "responses" => {
                "200" => { "description" => "Collection", "content" => { vnd => { "schema" => collection_schema } } },
              },
            },
            "post" => {
              "summary" => "Create #{tag}",
              "tags" => [tag],
              "security" => [{ "bearerAuth" => [] }],
              "requestBody" => { "required" => true, "content" => { vnd => { "schema" => request_schema } } },
              "responses" => {
                "201" => { "description" => "Created", "content" => { vnd => { "schema" => single_schema } } },
              },
            },
          },
          "/#{resource_type}/{id}" => {
            "get" => {
              "summary" => "Show #{tag}",
              "tags" => [tag],
              "security" => [{ "bearerAuth" => [] }],
              "parameters" => [id_param, include_param, fields_param],
              "responses" => {
                "200" => { "description" => "Resource", "content" => { vnd => { "schema" => single_schema } } },
                "404" => { "description" => "Not found" },
              },
            },
            "patch" => {
              "summary" => "Update #{tag}",
              "tags" => [tag],
              "security" => [{ "bearerAuth" => [] }],
              "parameters" => [id_param],
              "requestBody" => { "required" => true, "content" => { vnd => { "schema" => request_schema } } },
              "responses" => {
                "200" => { "description" => "Updated", "content" => { vnd => { "schema" => single_schema } } },
                "404" => { "description" => "Not found" },
              },
            },
            "delete" => {
              "summary" => "Destroy #{tag}",
              "tags" => [tag],
              "security" => [{ "bearerAuth" => [] }],
              "parameters" => [id_param],
              "responses" => {
                "204" => { "description" => "No Content" },
                "404" => { "description" => "Not found" },
              },
            },
          },
        }
      end

      def v3_custom_action_paths(model_class)
        paths = {}
        resource_type = model_class.model_name.plural
        tag = model_class.model_name.name
        custom_actions = ("Endpoints::#{tag}".constantize.instance_methods(false) rescue [])
        custom_actions.each do |action|
          definition = ("Endpoints::#{tag}".constantize.definitions[tag][action.to_sym] rescue nil)
          next unless definition
          definition.each { |_verb, spec| spec[:tags] = [tag] if spec.is_a?(Hash) }
          has_id = definition.any? { |_v, spec| spec.is_a?(Hash) && spec[:parameters]&.any? { |p| p[:in] == "path" } }
          path = "/#{resource_type}/custom_action/#{action}#{has_id ? "/{id}" : ""}"
          paths[path] = definition
        end
        paths
      end

      def v3_description
        <<~MD
          ## API v3 — JSON:API

          All resource endpoints follow the [JSON:API 1.0](https://jsonapi.org) specification.

          ### Authentication

          `POST /authenticate` → JWT in `Token` response header. Pass as `Authorization: Bearer <token>`.
          Every successful request renews the token — always read and store the new `Token` header.

          ### Content negotiation

          `Accept: application/vnd.api+json` (GET) · `Content-Type: application/vnd.api+json` (write requests).

          ### Filtering

          `?filter[field]=value` — validated against each model's `ransackable_attributes`.

          ### Sorting

          `?sort=field` (asc) · `?sort=-field` (desc) · `?sort=field1,-field2` (multi-field).

          ### Pagination

          `?page[number]=N&page[size]=N` — response includes `meta.total`.

          ### Sparse fieldsets

          `?fields[type]=field1,field2` — restrict attributes returned per resource type.

          ### Sideloading

          Default sideloads come from each model's `json_attrs[:include]`.
          Override with `?include=assoc1,assoc2` · suppress all with `?include=` (empty string).

          ### Info & utility endpoints

          `GET /info/version|heartbeat|roles|schema|dsl|translations|settings|swagger` — return plain JSON (not JSON:API).

          ### Raw SQL escape hatch

          `GET|POST /raw/sql` — SELECT-only; returns plain JSON array (not JSON:API).
        MD
      end
    end
  end
end
