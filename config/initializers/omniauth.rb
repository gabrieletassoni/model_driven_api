Rails.application.config.middleware.use OmniAuth::Builder do
  provider(
    :entra_id,
    {
      client_id:     ENV['ENTRA_CLIENT_ID'],
      client_secret: ENV['ENTRA_CLIENT_SECRET']
    }
  )
  provider :google_oauth2, ENV['GOOGLE_CLIENT_ID'], ENV['GOOGLE_CLIENT_SECRET']
end

OmniAuth.config.allowed_request_methods = %i[get]
OmniAuth.config.silence_get_warning = true