# require 'ransack'

Rails.application.routes.draw do
  scope ENV.fetch("RAILS_RELATIVE_URL_ROOT", "/") do
    if ThecoreAuthCommons.oauth_vars?
      # OmniAuth callbacks need these top-level paths:
      match "/auth/:provider/callback", to: redirect("/api/v2/auth/%{provider}/callback"), via: [:get, :post]
      match "/auth/failure", to: redirect("/api/v2/auth/failure"), via: [:get, :post]
    end
    namespace :api, constraints: { format: :json } do
      namespace :v2 do
        # Authentication via Oauth2 only if the environment variable is set
        if ThecoreAuthCommons.oauth_vars?
          namespace :auth do
            # Omniauth routes for OAuth2 authentication
            match ":provider/callback", to: "oauth#callback", via: [:get, :post]
            get :failure, to: "oauth#failure"
            get ":provider", to: redirect("/auth/%{provider}") # triggers OmniAuth middleware
            post :jwt, to: "oauth#exchange_token" # Optional endpoint to allow frontends to send the OAuth token
          end
        end

        resources :users

        namespace :info do
          get :version
          get :roles
          get :translations
          get :schema
          get :dsl
          get :heartbeat
          get :settings
          get :swagger
          get :openapi
        end

        namespace :raw do
          post :query
        end

        post "authenticate" => "authentication#authenticate"
        post ":ctrl/search" => "application#index"

        # Add a route with placeholders for custom actions, the custom actions routes have a form like: :ctrl/custom_action/:action_name or :ctrl/custom_action/:action_name/:id
        # Can have all the verbs, but the most common are: get, post, put, delete
        get ":ctrl/custom_action/:action_name", to: "application#index"
        get ":ctrl/custom_action/:action_name/:id", to: "application#show"
        post ":ctrl/custom_action/:action_name", to: "application#create"
        put ":ctrl/custom_action/:action_name/:id", to: "application#update"
        patch ":ctrl/custom_action/:action_name/:id", to: "application#update"
        delete ":ctrl/custom_action/:action_name/:id", to: "application#destroy"
        # Catchall routes
        # # CRUD Show
        get "*path/:id", to: "application#show"
        # # CRUD Index
        get "*path", to: "application#index"
        # # CRUD Create
        post "*path", to: "application#create"
        # CRUD Update
        put "*path/:id/multi", to: "application#update_multi"
        patch "*path/:id/multi", to: "application#update_multi"
        put "*path/:id", to: "application#update"
        patch "*path/:id", to: "application#patch"

        # # CRUD Delete
        delete "*path/:id/multi", to: "application#destroy_multi"
        delete "*path/:id", to: "application#destroy"
      end
    end
  end
end
