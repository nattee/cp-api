Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  get "login", to: "sessions#new"
  post "login", to: "sessions#create"
  delete "logout", to: "sessions#destroy"

  namespace :line do
    post "webhook", to: "webhook#callback"
  end

  resource :line_account, only: [:show, :create, :destroy], controller: "line_accounts"

  resources :programs
  resources :courses
  resources :staffs
  resources :students do
    collection do
      get :datatable
    end
  end
  resources :grades
  resources :users
  resources :chat_messages, only: [:index, :show]
  resources :data_imports, only: [:index, :new, :create, :show] do
    member do
      get :mapping
      patch :execute
      patch :retry_import
    end
  end

  get "dev/styleguide", to: "dev#styleguide" if Rails.env.development?

  root "users#index"
end
