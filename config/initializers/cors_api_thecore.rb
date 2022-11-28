# config/initializers/cors.rb
# Rails.application.config.middleware.insert_before 0, Rack::Cors do
#   allow do
#     origins '*'
#     resource '*',
#       headers: %w(Token),
#       methods: :any,
#       expose: %w(Token),
#       max_age: 600
#   end
# end

puts "Loading CORS"
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  # Allow Everything
  # Please override to your specific security needs in the actual application
  allow do
    origins '*'
    resource '*', headers: :any, methods: [:get, :post, :put, :patch, :delete, :options, :head]
  end
end