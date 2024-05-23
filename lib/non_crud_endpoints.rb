class NonCrudEndpoints
    attr_accessor :result
    cattr_accessor :definitions
    self.definitions = {}
    # Add a validation method which will be inherited by all the instances, and automatically run before any method call
    def initialize(m, params)
        # Rails.logger.debug "Initializing NonCrudEndpoints"
        # Showing the class name of the instance, and also, if there's a class inheriting from this one, the name of the child class
        # Rails.logger.debug "Class: #{self.class.name} - Child Class: #{self.class.superclass.name if self.class.superclass != Object}"
        # Check if self has the m method, if not, raise a NoMethodError
        raise NoMethodError, "The method #{m} does not exist in #{self.class.name}" unless self.respond_to? m
        # To avoid having conflicting keys from different classes, we will use a two levels object to store the definitions
        # the first level is the class name, and the second level is the method name
        self.definitions[self.class.name] ||= {}
        self.definitions[self.class.name][m.to_sym] ||= {}
        @definition = self.definitions[self.class.name][m.to_sym].with_indifferent_access

        # self.send(m, { explain: true }) rescue []
        validate_request(params)
        @result = self.send(m, params)
    end

    def validate_request(params)
        # If there is no definition, return
        return if @definition.blank?
        
        # Raise a ValidationError if the request does not match the definition of the verbs expected in the @definition hash
        #raise EndpointValidationError, "The verb \"#{params[:request_verb].presence || "No Verb Provided"}\" is not present in #{@definition.keys.join(", ")}." if @definition.keys.exclude? params[:request_verb]
        # Assuming @definition follows the openapi schema, we can check the request body and query parameters are correct
        
    end

    private

    def self.desc(endpoint, key, definition)
        self.definitions[endpoint] ||= {}
        self.definitions[endpoint][key] = definition
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

