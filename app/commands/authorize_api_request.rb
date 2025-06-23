class AuthorizeApiRequest
    prepend SimpleCommand
    
    def initialize(request = {})
        @headers = request.headers rescue {}
    end
    
    def call
        api_user
    end
    
    private
    
    attr_reader :headers
    
    def api_user
        Rails.logger.debug "AuthorizeApiRequest: api_user -> #{decoded_auth_token}"
        @api_user ||= (decoded_auth_token.blank? ? User.find(decoded_auth_token[:user_id]) : nil)
        unless @api_user.blank
            return @api_user
        else
            errors.add(:token, "Invalid or Expired token")
            return nil
        end
    end
    
    def decoded_auth_token
        Rails.logger.debug "AuthorizeApiRequest: decoded_auth_token -> http_auth_header -> #{http_auth_header}"
        @decoded_auth_token ||= (JsonWebToken.decode(http_auth_header) rescue nil)
        @decoded_auth_token
    end
    
    def http_auth_header
        Rails.logger.debug "AuthorizeApiRequest: http_auth_header - Authorization -> #{headers['Authorization']}"
        if headers['Authorization'].present?
            token = headers['Authorization'].split(' ').last
            Rails.logger.debug "AuthorizeApiRequest: http_auth_header - token -> #{token}"
            return token
        else
            errors.add(:token, "Missing token")
        end
        nil
    end
end