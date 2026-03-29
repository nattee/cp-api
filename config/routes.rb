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

  resources :semesters do
    resources :course_offerings, only: [:index, :new, :create], shallow: true
  end
  resources :course_offerings, only: [:show, :edit, :update, :destroy]
  resources :rooms
  resources :scrapes, only: [:index, :create, :show]

  controller :schedules do
    get "schedules", action: :index
    get "schedules/room", action: :room
    get "schedules/staff", action: :staff
    get "schedules/curriculum", action: :curriculum
    get "schedules/student", action: :student
    get "schedules/workload", action: :workload
    get "schedules/conflicts", action: :conflicts
  end

  resources :programs
  resources :courses
  resources :staffs
  resources :students do
    collection do
      get :datatable
    end
  end
  resources :grades
  resources :users do
    member do
      post :generate_line_code
      delete :unlink_line
    end
  end
  resources :chat_messages, only: [:index, :show]
  resources :api_events, only: [:index]
  resources :data_imports, only: [:index, :new, :create, :show] do
    member do
      get :mapping
      patch :execute
      patch :retry_import
    end
  end

  get "dev/styleguide", to: "dev#styleguide"

  root "users#index"
end
