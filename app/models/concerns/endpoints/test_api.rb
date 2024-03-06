module Endpoints::TestApi
    def self.test params
        # Define an explain var to be used to validate and document the action behavior when using ?explain=true in query string
        explain = {
            verbs: ["GET"],
            body: {},
            query: {},
            responses: {
                200 => {
                    message: :string,
                    params: {}
                },
                501 => {
                    error: :string
                }
            }
        }

        return explain, 200 if params[:explain] == "true"
        return { error: "This method responds only to #{explain[:verbs].join(", ")} requests" }, 501 if explain[:verbs].exclude? params[:request_verb]
        return { message: "Hello World From Test API Custom Action called test", params: params }, 200
    end
end
