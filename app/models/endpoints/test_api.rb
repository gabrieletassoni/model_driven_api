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
