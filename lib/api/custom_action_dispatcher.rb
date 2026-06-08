module Api
  class CustomActionDispatcher
    # Dispatch a custom action if the request signals one.
    # Returns false if this is not a custom action call.
    # Returns [true, body, status] when dispatched.
    # Raises NoMethodError if the action name is present but not found.
    def self.call(model, params, request)
      custom_action = if !params[:do].blank?
          params[:do]
        elsif request.url.include?("/custom_action/")
          params[:action_name]
        end
      return false unless custom_action

      params[:request_url] = request.url
      params[:remote_ip] = request.remote_ip
      params[:request_verb] = request.request_method
      params[:token] = extract_bearer(request)

      Rails.logger.debug("CustomActionDispatcher: #{custom_action} on #{model}")

      if model.respond_to?("custom_action_#{custom_action}")
        body, status = model.send("custom_action_#{custom_action}", params)
      elsif ("Endpoints::#{model}".constantize rescue false) &&
            "Endpoints::#{model}".constantize.instance_methods.include?(custom_action.to_sym)
        body, status = "Endpoints::#{model}".constantize.new(custom_action, params).result
      else
        raise NoMethodError
      end

      [true, body, status]
    end

    def self.extract_bearer(request)
      pattern = /^Bearer /
      header = request.headers["Authorization"]
      header.gsub(pattern, "") if header&.match(pattern)
    end
    private_class_method :extract_bearer
  end
end
