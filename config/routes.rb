Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  mount Rswag::Ui::Engine => "/api-docs"
  mount Rswag::Api::Engine => "/api-docs"

  namespace :api do
    namespace :v1 do
      resources :parts do
        resources :stock_movements, only: [ :index, :create ]
      end

      resources :executions, param: :service_order_uuid, only: [ :index, :show ] do
        member do
          post :start_diagnosis
          post :start_repair
          post :finish
        end
      end
    end
  end
end
