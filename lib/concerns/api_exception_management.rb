module ApiExceptionManagement
    extend ActiveSupport::Concern
    
    included do
        if Rails.env.production?
            rescue_from NoMethodError, with: :not_found!
            rescue_from CanCan::AccessDenied, with: :unauthorized!
            rescue_from AuthenticateUser::AccessDenied, with: :unauthenticated!
            rescue_from ActionController::RoutingError, with: :not_found!
            rescue_from ActiveModel::ForbiddenAttributesError, with: :fivehundred!
            rescue_from ActiveRecord::RecordInvalid, with: :invalid!
            rescue_from ActiveRecord::RecordNotFound, with: :not_found!
            rescue_from ActiveRecord::RecordNotUnique, with: :invalid!
            rescue_from EndpointValidationError, with: :api_error
        end
        
        def unauthenticated! exception = AuthenticateUser::AccessDenied.new
            response.headers['WWW-Authenticate'] = "Token realm=Application"
            return api_error status: 401, errors: exception.message
        end
        
        def unauthorized! exception = CanCan::AccessDenied.new
            return api_error status: 403, errors: exception.message
        end
        
        def not_found! exception = StandardError.new
            return api_error status: 404, errors: exception.message
        end
        
        def invalid! exception = StandardError.new
            return api_error status: 422, errors: exception.record.errors 
        end
        
        def fivehundred! exception = StandardError.new
            return api_error status: 500, errors: exception.message
        end
        
        def api_error(status: 501, errors: [])
            # puts errors.full_messages if !Rails.env.production? && errors.respond_to?(:full_messages)
            head status && return if errors.blank?
            
            # For retrocompatibility, I try to send back only strings, as errors
            errors_response = if errors.respond_to?(:full_messages) 
                # Validation Errors
                errors.full_messages.join(", ")
            elsif errors.respond_to?(:error)
                # Generic uncatched error
                errors.error
            elsif errors.respond_to?(:exception)
                # Generic uncatchd error, if the :error property does not exist, exception will
                errors.exception
            elsif errors.is_a? Array
                # An array of values, I like to have them merged
                errors.join(", ")
            else
                # Uncatched Error, comething I don't know, I must return the errors as it is
                errors
            end
            render json: {error: errors_response}, status: status
        end
    end
end