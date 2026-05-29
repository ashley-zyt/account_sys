Rails.application.routes.draw do
  devise_for :admins

  namespace :admin do
    root to: "dashboard#index"
    resources :accounts, only: [:index, :show, :new, :create, :edit, :update]
    resources :move_tasks, only: [:index, :show]
    resources :jianying_tasks, only: [:index, :show]
    resources :operation_tasks, only: [:index, :show, :new, :create] do
      collection do
        get :get_upload_params
      end
    end
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
      end
      member do
        get :edit_modal
      end
    end
    resources :post_stats, only: [:index]
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
      # 发文数据接口
      post "post_stats", to: "post_stats#create"
      post "post_stats/batch", to: "post_stats#batch_create"
      # 账号数据接口
      get "accounts", to: "accounts#index"
      get "accounts/:id", to: "accounts#show"
      get "accounts/by_name", to: "accounts#by_name"
      get "accounts/themes", to: "accounts#themes"
    end
  end

  root to: "admin/dashboard#index"
end