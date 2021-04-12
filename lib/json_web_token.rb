class JsonWebToken
    class << self
      def encode(payload, expiry = 15.minutes.from_now.to_i)
        ::JWT.encode(payload.merge(exp: expiry), ::Rails.application.credentials.dig(:secret_key_base).presence||ENV["SECRET_KEY_BASE"])
      end
      
      def decode(token)
        body = ::JWT.decode(token, ::Rails.application.credentials.dig(:secret_key_base).presence||ENV["SECRET_KEY_BASE"])[0]
        ::HashWithIndifferentAccess.new body
      rescue
        nil
      end
    end
  end