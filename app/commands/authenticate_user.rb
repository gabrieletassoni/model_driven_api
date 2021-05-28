class AuthenticateUser
    class AccessDenied < StandardError
        def message more = "AuthenticationError"
            more
        end
    end
    prepend SimpleCommand
    
    def initialize(*args)
        first_arg = args.first
        if !first_arg[:email].blank? && !first_arg[:password].blank?
            @email = first_arg[:email]
            @password = first_arg[:password]
        elsif !first_arg[:access_token].blank?
            @access_token = first_arg[:access_token]
        end
    end
    
    def call
        current_u = api_user
        if !current_u.blank? && result = JsonWebToken.encode(user_id: current_u.id)
            # The token is created and the api_user exists => Invalidating all the previous tokens
            # Since this is a new login and I don't care from where it comes, new logins always
            # Invalidate older tokens
            UsedToken.where(user_id: api_user.id).update(is_valid: false) if ENV["ALLOW_MULTISESSIONS"] == "false"
            return {jwt: result, user: current_u}
        end
        nil
    end
    
    private
    
    attr_accessor :email, :password, :access_token
    
    def api_user
        if !email.blank? && !password.blank?
            user = User.find_by(email: email)
            # Verify the password.
            raise AccessDenied if user.blank? && user.authenticate(password).blank?
        elsif !access_token.blank?
            user = User.find_by(access_token: access_token)
        end

        raise AccessDenied unless user.present?
        
        return user
    end
    
end