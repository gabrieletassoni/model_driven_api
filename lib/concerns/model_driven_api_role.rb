module ModelDrivenApiRole
    extend ActiveSupport::Concern
    
    included do
        ## DSL (AKA what to show in the returned JSON)
        # Use @@json_attrs to drive json rendering for 
        # API model responses (index, show and update ones).
        # For reference:
        # https://api.rubyonrails.org/classes/ActiveModel/Serializers/JSON.html
        # The object passed accepts only these keys:
        # - only: list [] of model field names in symbol notation to be shown in JSON 
        #       serialization.
        # - except: exclude these fields from the JSON serialization, is a list []
        #        of model field names in symbol notation.
        # - methods: include the result of some methods defined in the model (virtual
        #       fields).
        # - include: include associated models, it's a list [] of hashes {} which also 
        #       accepts the [:only, :except, :methods, :include] keys.
        cattr_accessor :json_attrs
        self.json_attrs = ModelDrivenApi.smart_merge((json_attrs || {}), {
            except: [
                :lock_version,
                :created_at,
                :updated_at
            ],
            include: [users: {
                only: [:id]
            }]
        })

        ## CUSTOM ACTIONS
        # Here you can add custom actions to be called from the API
        # The action must return an serializable (JSON) object.

        # Here you can find an example *without* ID, in the API it could be called like this:
        # GET /api/v2/:controller?do=test&parameter=sample
        # def self.custom_action_test params=nil
        #     { test: [ :first, :second, :third ], params: params}
        # end

        # Here you can find an example *with* ID, in the API it could be called like this:
        # GET /api/v2/:controller/:id?do=test_with_id&parameter=sample
        # def self.custom_action_test_with_id id=nil, params=nil
        #     { test: [ :first, :second, :third ], id: id, params: params}
        # end
    end
end