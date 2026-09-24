require 'endpoint_validation_error'
require 'non_crud_endpoints'
require 'thecore_backend_commons'
require 'rack/cors'
require 'ransack'
require 'jwt'
require 'json_web_token'
require "kaminari"
require "pagy"
# require "multi_json"
require "simple_command"

require 'concerns/api_exception_management'

require 'deep_merge/rails_compat'

require "model_driven_api/engine"

require "safe_sql_executor"
require "api/resource_attribute_set"
require "api/model_resolver"
require "api/custom_action_dispatcher"
require "api/open_api/base"
require "api/open_api/v2"
require "api/open_api/v3"
require "api/v3/serializer_factory"

module ModelDrivenApi
  UTC_ZONE_NAMES = %w[UTC Etc/UTC].freeze

  # Raises unless the app is UTC-only: +time_zone+ is config.time_zone, +db_zone+ is
  # config.active_record.default_timezone (nil = Rails' default, :utc). Called at boot by
  # ModelDrivenApi::Engine's :enforce_utc_time_zone initializer.
  def self.enforce_utc!(time_zone, db_zone = nil)
    unless UTC_ZONE_NAMES.include?(time_zone.to_s)
      raise ArgumentError, "model_driven_api requires config.time_zone to be UTC (got #{time_zone.inspect}). " \
                           "The backend is UTC-only; localize dates in the frontend instead."
    end
    return if db_zone.nil? || db_zone.to_sym == :utc

    raise ArgumentError, "model_driven_api requires config.active_record.default_timezone to be :utc " \
                         "(got #{db_zone.inspect})."
  end

  def self.smart_merge src, dest
      src.deeper_merge! dest, {
          extend_existing_arrays: true, 
          merge_hash_arrays: true
      }
      src
  end
end
