module Api
  class ModelResolver
    class NotFound < StandardError; end

    # Resolve model from params, controller_path, or controller_name.
    # Returns nil when no class can be resolved (info/utility controllers use this path).
    # Raises NotFound when a class is resolved but is not a concrete ActiveRecord model (and not TestApi).
    #
    # The names come from the request path, so a resolved class is only ever inspected, never
    # instantiated: checking a model with `.new` used to run the constructor of any class the
    # path named (GET /api/v2/tempfiles created a file on the server).
    def self.resolve(params, controller_path, controller_name)
      model = [
        params[:ctrl],
        params[:path].to_s.split("/").first,
        controller_path,
        controller_name
      ].lazy.filter_map { |name| name.to_s.classify.safe_constantize }.first
      raise NotFound if model && model != TestApi && !model?(model)

      model
    end

    def self.model?(klass)
      klass.is_a?(Class) && klass < ActiveRecord::Base && !klass.abstract_class?
    end
    private_class_method :model?
  end
end
