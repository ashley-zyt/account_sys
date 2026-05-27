Rails.application.routes.draw do
  devise_for :admins

  namespace :admin do
    root to: "dashboard#index"
    resources :accounts, only: [:index, :show, :new, :create, :edit, :update]
    resources :move_tasks, only: [:index, :show]
    resources :jianying_tasks, only: [:index, :show]
    resources :browsers, only: [:index, :show, :new, :create, :edit, :update]
    resources :task_logs, only: [:index, :show]
    resources :kols, only: [:index, :show, :new, :create, :edit, :update, :destroy] do
      member do
        get :initiate_contact
        post :start_conversation
      end
    end
    resources :conversations, only: [:index, :show] do
      member do
        post :update_status
      end
    end
    resources :message_templates, only: [:index, :new, :create, :edit, :update, :destroy]
    resources :themes, only: [:index, :create, :edit, :update, :destroy] do
      collection do
        get :new_modal
        get :edit_modal
      end
    end
  end

  namespace :api do
    namespace :v1 do
      post "video/receive", to: "video_receive#create"
      get "task/fetch_next_executable_task", to: "tasks#fetch_next_executable_task"
      get "task/report", to: "tasks#report"
      get "check/accounts"
      get "check/valid_proxies"
      post "check/update_account_status"
      get "kol/fetch_conversation", to: "kols#fetch_conversation"
      get "kol/get_latest_message", to: "kols#get_latest_message"
    end
  end

  root to: "admin/dashboard#index"
end