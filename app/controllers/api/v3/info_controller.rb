class Api::V3::InfoController < Api::V2::InfoController
  # Override openapi/swagger to generate a v3-accurate spec.
  # All other info actions (version, roles, heartbeat, ntp, translations,
  # schema, dsl, settings) are inherited unchanged — they return plain JSON
  # and are version-agnostic.
  def openapi
    uri = URI(request.url)
    spec = {
      "openapi" => "3.0.0",
      "info" => {
        "title" => "#{Settings.ns(:main).app_name} API",
        "description" => Api::OpenApi::V3.new(ApplicationRecord.subclasses, request).description,
        "version" => "v3",
      },
      "servers" => [
        {
          "url" => "#{uri.scheme}://#{uri.host}#{":#{uri.port}" if uri.port.present?}/api/v3",
          "description" => "JSON:API v3 base URL",
        },
      ],
      "components" => {
        "securitySchemes" => {
          "bearerAuth" => {
            "type" => "http",
            "scheme" => "bearer",
            "bearerFormat" => "JWT",
          },
        },
      },
      "security" => [{ "bearerAuth" => [] }],
      "paths" => Api::OpenApi::V3.new(ApplicationRecord.subclasses, request).generate,
    }
    render json: spec.to_json, status: 200
  end

  alias_method :swagger, :openapi
end
