# module Endpoints
#   def self.method_missing(m, *args, &block)
#     # return explain, 200 if m == :explain
#     validate_request(m, *args, &block)
#     if Endpoints::TestApi.methods.include?(m.to_s)
#       Endpoints::TestApi.send(m, *args, &block)
#     else
#       super
#     end
#   end

#   def self.validate_request definition, params
#     return definition, 200 if params[:explain] == "true"
#     # Raise a ValidationError if the request does not match the definition

#     # Validate the request verb

#     raise { error: "This method responds only to #{explain[:verbs].join(", ")} requests" }, 501 if explain[:verbs].exclude? params[:request_verb]
#   end
class Endpoints::TestApi < NonCrudEndpoints
  def test(params)
    # Define an explain var to be used to validate and document the action behavior when using ?explain=true in query string
    explain = {
      verbs: ["GET", "POST"],
      body: {
        messages: {
          type: :array,
          optional: true,
          items: {
            type: :string,
            optional: false
          }
        },
        is_connected: {
          type: :boolean,
          optional: false
        },
        user: {
          type: :object,
          optional: true,
          properties: {
            name: {
              type: :string,
              optional: false
            },
            age: {
              type: :integer,
              optional: true
            }
          }
        }
      },
      query: {
        explain: {
          type: :boolean,
          optional: true
        }
      },
      responses: {
        200 => {
          message: :string,
          params: {},
        },
        501 => {
          error: :string,
        },
      },
    }
    return explain, 200 if params[:explain].to_s == "true" && !explain.blank?
    
    
    return { message: "Hello World From Test API Custom Action called test", params: params }, 200
  end
end
# end
