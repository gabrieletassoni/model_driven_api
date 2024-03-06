# require 'ransack'

Rails.application.routes.draw do
    # REST API (Stateless)
    namespace :api, constraints: { format: :json } do
        namespace :v2 do
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

            post "authenticate" => "authentication#authenticate"
            post ":ctrl/search" => 'application#index'

            # Add a route with placeholders for custom actions, the custom actions routes have a form like: :ctrl/custom_action/:action_name or :ctrl/custom_action/:action_name/:id
            # Can have all the verbs, but the most common are: get, post, put, delete
            get ":ctrl/custom_action/:action_name", to: 'application#index'
            get ":ctrl/custom_action/:action_name/:id", to: 'application#show'
            post ":ctrl/custom_action/:action_name", to: 'application#create'
            put ":ctrl/custom_action/:action_name/:id", to: 'application#update'
            patch ":ctrl/custom_action/:action_name/:id", to: 'application#update'
            delete ":ctrl/custom_action/:action_name/:id", to: 'application#destroy'
            # Catchall routes
            # # # CRUD Show
            # get '*path/:id', to: 'application#show'
            # # # CRUD Index
            # get '*path', to: 'application#index'
            # # # CRUD Create
            # post '*path', to: 'application#create'
            # # CRUD Update
            put '*path/:id/multi', to: 'application#update_multi'
            patch '*path/:id/multi', to: 'application#update_multi'
            # put '*path/:id', to: 'application#update'
            # patch '*path/:id', to: 'application#patch'

            # # CRUD Delete
            delete '*path/:id/multi', to: 'application#destroy_multi'
            # delete '*path/:id', to: 'application#destroy'
        end
    end
end
