module Api::V2::Auth
  class OauthController < ActionController::API
    # L'identità arriva solo da request.env['omniauth.auth'], che il middleware OmniAuth imposta
    # dopo aver verificato il login col provider; mai dai parametri della richiesta, che chiunque
    # può inviare (fino alla 3.12.1 bastava una POST con email= per avere il JWT di quell'utente).
    def callback
      auth = request.env['omniauth.auth']
      info = auth&.info
      user = info && ThecoreAuthCommons.check_user(info.email,
                                                   info.first_name.presence || info.name,
                                                   info.last_name,
                                                   auth.provider)

      # A locked user gets the same answer as an unknown one (Odoo #6051).
      unless user&.active_for_authentication?
        render json: { error: "User not registered" }, status: :unauthorized
        return
      end

      token = JsonWebToken.encode(user_id: user.id)

      if ENV["ALLOW_MULTISESSIONS"] == "false"
        UsedToken.where(user_id: user.id).update_all(is_valid: false)
        UsedToken.create!(token: token, user_id: user.id)
      end

      # redirect_url = "#{ENV['FRONTEND_URL']}?token=#{token}"
      # redirect_to redirect_url
      response.set_header("Token", JsonWebToken.encode(user_id: user.id))
      render json: user, status: :ok
    end

    def failure
      render json: { error: "OAuth authentication failed" }, status: :unauthorized
    end
  end
end