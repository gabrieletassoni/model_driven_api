module AuthHelpers
  def auth_headers_for(user)
    token = JsonWebToken.encode(user_id: user.id)
    {
      "Authorization" => "Bearer #{token}",
      "Content-Type" => "application/vnd.api+json",
      "Accept" => "application/vnd.api+json"
    }
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request
end
