puts "Loading CORS"
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  # Allow Everything
  # Please override to your specific security needs in the actual application
  allow do
    origins '*'
    resource '*',
      headers: %w(accept app authorization cache-control client-security-token content-type dnt enc-data if-modified-since keep-alive lang origin session-id token user-agent user-data x-requested-with),
      methods: [:get, :post, :put, :patch, :delete, :options, :head],
      expose: %w(authorization content-length token),
      max_age: 600
  end
end
