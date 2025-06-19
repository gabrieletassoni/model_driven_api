module Api::V2::Auth
  class OauthController < ActionController::API
    def callback
      email = params['email']

      user = User.find_or_create_by(email: email) do |u|
        u.name = params['given_name']
        u.surname = params['family_name']
        u.password = u.password_confirmation = ThecoreAuthCommons.generate_secure_password
        u.auth_source = params['provider'] # 'google' or 'microsoft'
        u.admin = true
      end
      unless user
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

    def exchange_token
      provider_token = params[:provider_token]
      provider = params[:provider] # 'google' or 'microsoft'

      user_info = case provider
      when 'google'
        uri = URI("https://www.googleapis.com/oauth2/v3/userinfo")
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
          req = Net::HTTP::Get.new(uri)
          req["Authorization"] = "Bearer #{provider_token}"
          http.request(req)
        end
        JSON.parse(res.body)
      when 'microsoft'
        uri = URI("https://graph.microsoft.com/v1.0/me")
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
          req = Net::HTTP::Get.new(uri)
          req["Authorization"] = "Bearer #{provider_token}"
          http.request(req)
        end
        JSON.parse(res.body)
      else
        return render json: { error: "Unknown provider" }, status: :unprocessable_entity
      end

      email = user_info["mail"] || user_info["email"] || user_info["userPrincipalName"]
      user = User.find_by(email: email)

      if user.nil?
        return render json: { error: "User not registered" }, status: :unauthorized
      end

      response.set_header("Token", JsonWebToken.encode(user_id: user.id))
      render json: user, status: :ok
    end
  end
end