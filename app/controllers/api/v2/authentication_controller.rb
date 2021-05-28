class Api::V2::AuthenticationController < ActionController::API
    include ::ApiExceptionManagement

    def authenticate
        command = !params[:atoken].blank? && User.column_names.include?("access_token") ? AuthenticateUser.call(access_token: params[:atoken]) : AuthenticateUser.call(email: params[:auth][:email], password: params[:auth][:password])
        
        if command.success?
            response.headers['Token'] = command.result[:jwt]
            # head :ok
            render json: command.result[:user].to_json(User.json_attrs), status: 200
        end
    end
end