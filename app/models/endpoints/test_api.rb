class Endpoints::TestApi < NonCrudEndpoints
  self.desc :test, {
    # Define the action name using openapi swagger format
    get: {
      summary: "Test API Custom Action",
      description: "This is a test API custom action",
      operationId: "test",
      tags: ["Test"],
      parameters: [
        {
          name: "explain",
          in: "query",
          description: "Explain the action by returning this openapi schema",
          required: true,
          schema: {
            type: "boolean"
          }
        }
      ],
      responses: {
        200 => {
          description: "The openAPI json schema for this action",
          content: {
            "application/json": {
              schema: {
                type: "object",
                additionalProperties: true
              }
            }
          }
        },
        501 => {
          error: :string,
        }
      }
    },
    post: {
      summary: "Test API Custom Action",
      description: "This is a test API custom action",
      operationId: "test",
      tags: ["Test"],
      requestBody: {
        required: true,
        content: {
          "application/json": {}
        }
      },
      responses: {
        200 => {
          description: "The openAPI json schema for this action",
          # This will return the object with a message string and a params object
          content: {
            "application/json": {
              schema: {
                type: "object",
                properties: {
                  message: {
                    type: "string"
                  },
                  params: {
                    type: "object",
                    additionalProperties: true
                  }
                }
              }
            }
          }
        },
        501 => {
          error: :string,
        }
      }
    }
  }
  def test(params)    
    return { message: "Hello World From Test API Custom Action called test", params: params }, 200
  end
end
