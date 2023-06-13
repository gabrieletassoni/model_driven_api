require 'thecore_backend_commons'
require 'rack/cors'
require 'ransack'
require 'jwt'
require 'json_web_token'
require "kaminari"
# require "multi_json"
require "simple_command"

require 'concerns/api_exception_management'

require 'deep_merge/rails_compat'

require "model_driven_api/engine"

module ModelDrivenApi
  def self.smart_merge src, dest
      src.deeper_merge! dest, {
          extend_existing_arrays: true, 
          merge_hash_arrays: true
      }
      src
  end
end
