Rails.application.routes.draw do
  devise_for :admins

  namespace :admin do
    root to: "dashboard#index"
    resources :accounts, only: [:index, :show, :new, :create, :edit, :update]
    resources :move_tasks, only: [:index, :show]
    resources :jianying_tasks, only: [:index, :show, :destroy]
    resources :operation_tasks, only: [:index, :show, :new, :create, :destroy] do
      collection do
        get :oss_signature
        get :setup_cors
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
    resources :post_stats, only: [:index] do
      get :export, on: :collection
    end
    resources :grok_image_resources, only: [:index, :new, :create, :destroy] do
      collection do
        get :oss_signature
        get :setup_cors
      end
    end
    resources :red_note_keywords, only: [:index, :show, :new, :create, :edit, :update, :destroy] do
      member do
        post :create_task
        post :sync_task
      end
      collection do
        post :batch_create_task
        post :sync_status
        get  :settings
        patch :update_settings
      end
    end
    resources :grok_tasks, only: [:index, :show, :new, :create, :edit, :update, :destroy]
    resources :heygen_tasks, only: [:index, :show, :new, :create, :edit, :update, :destroy]
    resources :operation_logs, only: [:index]
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
      get "post_stats/browsers_with_active_accounts", to: "post_stats#browsers_with_active_accounts"
      # 账号数据接口
      get "accounts", to: "accounts#index"
      get "accounts/:id", to: "accounts#show"
      get "accounts/by_name", to: "accounts#by_name"
      get "accounts/themes", to: "accounts#themes"
      # 运营任务接口
      get "operation_tasks/fetch", to: "tasks#fetch_operation_task"
      post "operation_tasks/report", to: "tasks#report"
      # Grok接口
      get "grok/images", to: "grok#images"
      get "grok/video_url", to: "grok#video_url"
      post "grok/save_video", to: "grok#save_video"
      # 认证接口
      post "auth/login", to: "auth#login"
      # RedNote接口
      post "red_note/keywords", to: "red_note#keywords"
      # 剪映任务批量接收
      post "jianying_tasks/batch", to: "jianying_tasks#batch"
    end
  end

  root to: "admin/dashboard#index"
end