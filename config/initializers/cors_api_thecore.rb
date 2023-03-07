puts "Loading CORS"
# config/initializers/cors_api_thecore.rb
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  #   # Allow Everything
  #   # Please override to your specific security needs in the actual application
  allow do
    origins '*'
    resource '*',
      headers: %w(app lang enc-data user-data session-id x-requested-with content-type origin authorization accept client-security-token Accept Authorization Cache-Control Content-Type DNT If-Modified-Since Keep-Alive Origin User-Agent X-Requested-With Token),
      methods: [:get, :post, :put, :patch, :delete, :options, :head],
      expose: %w(authorization Authorization Content-Length Token),
      max_age: 600
  end
end
