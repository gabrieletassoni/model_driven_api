module Endpoints::TestApi
    def self.test params
        return { message: "Hello World From Test API Custom Action called test", params: params }, 200
    end
end