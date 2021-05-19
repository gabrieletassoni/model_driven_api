class AuthenticateUser
    class AccessDenied < StandardError
        def message more = "AuthenticationError"
            more
        end
    end
    prepend SimpleCommand
    
    def initialize(*args)
        if !args.email.blank? && !args.password.blank?
            @email = args.email
            @password = args.password
        elsif !args.access_token.blank?
            @access_token = args.access_token
        end
    end
    
    def call
        if !api_user.blank? && result = JsonWebToken.encode(user_id: api_user.id)
            # The token is created and the api_user exists => Invalidating all the previous tokens
            # Since this is a new login and I don't care from where it comes, new logins always
            # Invalidate older tokens
            UsedToken.where(user_id: api_user.id).update(valid: false)
            return result
        end
        nil
    end
    
    private
    
    attr_accessor :email, :password, :access_token
    
    def api_user
        if !email.blank? && !password.blank?
            user = User.find_by(email: email)
            
            # Verify the password. You can create a blank method for now.
            raise AccessDenied if user.blank? && user.authenticate(password).blank?
        elsif !access_token.blank?
            user = User.find_by(access_token: access_token)
        end

        raise AccessDenied unless user.present?
        
        return user
    end
    
end