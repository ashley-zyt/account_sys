Rails.application.routes.draw do
  devise_for :admins

  namespace :admin do
    root to: "dashboard#index"
    resources :accounts, only: [:index, :show, :new, :create]
    resources :move_tasks, only: [:index, :show]
    resources :browsers, only: [:index, :show, :new, :create]
    resources :task_logs, only: [:index, :show]
  end

  namespace :api do
    namespace :v1 do
      post "video/receive", to: "video_receive#create"
    end
  end

  root to: "admin/dashboard#index"
end
