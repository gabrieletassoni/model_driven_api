class JsonWebToken
  class << self
    def encode(payload, expiry = ENV.fetch('SESSION_TIMEOUT_IN_MINUTES', 31).to_i.minutes.from_now.to_i)
      result = ::JWT.encode(payload.merge(exp: expiry), signing_key)
      # Store the created token into the DB for later checks if is invalid
      # In a public environment management, without login, it has no interest, so I don't pollute the DB
      UsedToken.find_or_create_by(token: result, user_id: payload[:user_id]) if ENV["ALLOW_MULTISESSIONS"] == "false"
      result
    end

    def decode(token)
      # Check if the passed token is present and valid into the UsedToken
      raise "Token is invalidated by new login" if !UsedToken.exists?(token: token, is_valid: true) && ENV["ALLOW_MULTISESSIONS"] == "false"
      body = verified_payload(token)
      Rails.logger.debug "JsonWebToken: decode -> body -> #{body}"
      ::HashWithIndifferentAccess.new body
    # rescue
    #   nil
    end

    private

    def signing_key
      ::Rails.application.credentials.dig(:secret_key_base).presence||ENV["SECRET_KEY_BASE"]
    end

    # After a SECRET_KEY_BASE rotation, a token signed with the previous key is still accepted until
    # SECRET_KEY_BASE_PREVIOUS_EXPIRES_AT (ISO 8601), so app users never log in again: every authenticated
    # response renews the token with the current key. The previous key may be public, so it is never
    # trusted without an expiry, and only a bad signature falls back to it (an expired token stays expired).
    def verified_payload(token)
      ::JWT.decode(token, signing_key)[0]
    rescue ::JWT::VerificationError
      previous = previous_signing_key or raise
      ::JWT.decode(token, previous)[0]
    end

    def previous_signing_key
      key = ENV["SECRET_KEY_BASE_PREVIOUS"].presence or return
      expires_at = Time.iso8601(ENV["SECRET_KEY_BASE_PREVIOUS_EXPIRES_AT"].to_s) rescue nil
      key if expires_at && Time.current < expires_at
    end
  end
end
