class JsonWebToken
  class << self
    def encode(payload, expiry = 15.minutes.from_now.to_i)
      result = ::JWT.encode(payload.merge(exp: expiry), ::Rails.application.credentials.dig(:secret_key_base).presence||ENV["SECRET_KEY_BASE"])
      # Store the created token into the DB for later checks if is invalid
      UsedToken.create(token: result, user_id: payload[:user_id])
      result
    end
    
    def decode(token)
      # Check if the passed token is present and valid into the UsedToken 
      raise "Token is invalidated by new login" unless UsedToken.exists?(token: token, is_valid: true)
      body = ::JWT.decode(token, ::Rails.application.credentials.dig(:secret_key_base).presence||ENV["SECRET_KEY_BASE"])[0]
      ::HashWithIndifferentAccess.new body
    rescue
      nil
    end
  end
end