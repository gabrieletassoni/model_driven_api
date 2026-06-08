module Api
  class ModelResolver
    class NotFound < StandardError; end

    # Resolve model from params, controller_path, or controller_name.
    # Returns nil when no class can be resolved (info/utility controllers use this path).
    # Raises NotFound when a class is resolved but is not an ActiveRecord model (and not TestApi).
    def self.resolve(params, controller_path, controller_name)
      model = (params[:ctrl].classify.constantize rescue
               params[:path].split("/").first.classify.constantize rescue
               controller_path.classify.constantize rescue
               controller_name.classify.constantize rescue
               nil)
      if model && model != TestApi
        raise NotFound unless (model.new.is_a?(ActiveRecord::Base) rescue false)
      end
      model
    end
  end
end
