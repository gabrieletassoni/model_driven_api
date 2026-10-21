module ModelDrivenApi
  class Engine < ::Rails::Engine
    # appending migrations to the main app's ones
    initializer :register_json_api_mime_type do
      Mime::Type.register "application/vnd.api+json", :json_api unless Mime[:json_api]
      ActionDispatch::Request.parameter_parsers[:json_api] =
        ActionDispatch::Request.parameter_parsers[:json]
    end

    # The backend works exclusively in UTC: every thecore app must keep Rails' default
    # `config.time_zone = "UTC"` (and ActiveRecord's default `:utc` storage), so every datetime
    # the API renders is UTC ("...Z") and localization is left entirely to the frontends.
    # Values a model deliberately localizes (e.g. TimeZoneAware's `_server_tz`/`_record_tz`)
    # are the only ones rendered with an offset. This replaces the old global
    # TimeWithZone#as_json -> utc monkey-patch (see config/initializers/time_with_zone.rb for
    # why that was removed). Runs before Rails applies the zone, so a misconfigured app fails
    # at boot instead of silently rendering local times.
    initializer :enforce_utc_time_zone, before: "active_support.initialize_time_zone" do |app|
      db_zone = app.config.active_record.default_timezone if app.config.respond_to?(:active_record)
      ModelDrivenApi.enforce_utc!(app.config.time_zone, db_zone)
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
