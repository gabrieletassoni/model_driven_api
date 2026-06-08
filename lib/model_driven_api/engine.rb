module ModelDrivenApi
  class Engine < ::Rails::Engine
    # appending migrations to the main app's ones
    initializer :register_json_api_mime_type do
      Mime::Type.register "application/vnd.api+json", :json_api unless Mime[:json_api]
      ActionDispatch::Request.parameter_parsers[:json_api] =
        ActionDispatch::Request.parameter_parsers[:json]
    end

    initializer :append_migrations do |app|
      unless app.root.to_s == root.to_s
        config.paths["db/migrate"].expanded.each do |expanded_path|
          app.config.paths["db/migrate"] << expanded_path
        end
      end
    end
  end
end
