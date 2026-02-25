Rails.application.routes.draw do
  devise_for :admins

  namespace :admin do
    root to: "dashboard#index"
    resources :accounts, only: [:index, :show, :new, :create, :edit, :update]
    resources :move_tasks, only: [:index, :show]
    resources :browsers, only: [:index, :show, :new, :create, :edit, :update]
    resources :task_logs, only: [:index, :show]
  end

  namespace :api do
    namespace :v1 do
      post "video/receive", to: "video_receive#create"
      get "task/fetch_next_executable_task", to: "tasks#fetch_next_executable_task"
    end
  end

  root to: "admin/dashboard#index"
end
