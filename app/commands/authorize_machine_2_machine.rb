class AuthorizeMachine2Machine
    prepend SimpleCommand
    
    def initialize(headers = {})
        @headers = headers
    end
    
    def call
        api_user
    end
    
    private
    
    attr_reader :headers
    
    def api_user
        token = http_auth_header
        user = User.find_by(access_token: token) unless token.blank?
        @api_user = user if user
        @api_user || errors.add(:token, "Invalid token") && nil
    end
    
    def http_auth_header
        if headers['Machine2Machine'].present?
            return headers['Machine2Machine'].split(' ').last
        else
            errors.add(:token, "Missing token")
        end
        nil
    end
end