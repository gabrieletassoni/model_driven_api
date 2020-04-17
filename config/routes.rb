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
            end

            post "authenticate" => "authentication#authenticate"
            post ":ctrl/search" => 'application#index'

            # Catchall routes
            # # CRUD Show
            get '*path/:id', to: 'application#show'
            # # CRUD Index
            get '*path', to: 'application#index'
            # # CRUD Create
            post '*path', to: 'application#create'
            # # CRUD Update
            put '*path/:id', to: 'application#update'
            # # CRUD DElete
            delete '*path/:id', to: 'application#destroy'
        end
    end
end
