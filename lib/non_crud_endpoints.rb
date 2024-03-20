class NonCrudEndpoints
    attr_accessor :result
    cattr_accessor :definitions
    self.definitions = {}
    # Add a validation method which will be inherited by all the instances, and automatically run before any method call
    def initialize(m, params)
        # Check if self hase the m method, if not, raise a NoMethodError
        raise NoMethodError, "The method #{m} does not exist in #{self.class.name}" unless self.respond_to? m
        @definition = self.definitions[m.to_sym].with_indifferent_access

        # self.send(m, { explain: true }) rescue []
        validate_request(params)
        @result = self.send(m, params)
    end

    def validate_request(params)
        # If there is no definition, return
        return if @definition.blank?
        # puts "Called Class is: #{self.class}"
        # puts "Which is son of: #{self.class.superclass}"
        # body_mandatory_keys = definition[:body].select { |k, v| v[:optional] == false }.keys
        # query_mandatory_keys = definition[:query].select { |k, v| v[:optional] == false }.keys
        # # Raise a ValidationError if the request does not match the definition
        # raise EndpointValidationError, "The verb \"#{params[:request_verb].presence || "No Verb Provided"}\" is not present in #{definition.keys.join(", ")}." if definition.keys.exclude? params[:request_verb]
        # # Raise an exception if the verb is put or post and the body keys in definition are not all present as params keys, both params and definition[:body] can have nested objects
        # raise EndpointValidationError, "The request body does not match the definition: in #{params[:request_verb]} requests all of the params must be present in definition. The body definition is #{definition[:body]}." if params[:request_verb] != "GET" && (body_mandatory_keys & params.keys) != body_mandatory_keys
        # # Raise an exception if the verb is put or post and the body keys in definition are not all present as params keys, both params and definition[:body] can have nested objects
        # raise EndpointValidationError, "The request query does not match the definition. The query definition is: #{definition[:query]}." if (query_mandatory_keys & params.keys) != query_mandatory_keys
        # # Rais if the type of the param is not the same as the definition
        # definition[:body].each do |k, v|
        #     next if params[k].nil?
        #     computed_type = get_type(params[k])
        #     raise EndpointValidationError, "The type of the param #{k} is not the same as the definition. The definition is #{v[:type]} and the param is #{computed_type}." if v[:type] != computed_type
        # end
    end

    private

    def self.desc(key, definition)
        self.definitions[key] = definition
    end

    def get_type(type)
        case type
        when String
            :string
        when Integer
            :integer
        when Float
            :number
        when TrueClass, FalseClass
            :boolean
        when Array
            :array
        when Hash
            :object
        else
            :undefined
        end
    end
end

