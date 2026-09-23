Rails.application.routes.draw do
  devise_for :admins

  namespace :admin do
    root to: "dashboard#index"
    resources :data_alerts, only: [:index] do
      collection do
        get :account
      end
    end
    resources :accounts, only: [:index, :show, :new, :create, :edit, :update, :destroy] do
      member do
        post :toggle_warmup
        post :refresh_stats
      end
      collection do
        get :shipinhao_login_qrcode
        get :shipinhao_login_qrcode_data
        get :export
      end
    end
    resources :move_tasks, only: [:index, :show] do
      member do
        post :execute
      end
    end
    resources :hunjian_tasks, only: [:index, :show] do
      member do
        post :execute
      end
    end
    resources :move_videos, only: [:index, :show]
    resources :jianying_tasks, only: [:index, :show, :destroy] do
      collection do
        delete :batch_destroy
      end
      member do
        post :execute
      end
    end
    resources :huasheng_tasks, only: [:index, :show, :destroy] do
      collection do
        delete :batch_destroy
      end
      member do
        post :execute
      end
    end
    resources :notebooklm_tasks, only: [:index, :show, :destroy] do
      collection do
        delete :batch_destroy
      end
      member do
        post :execute
      end
    end
    resources :operation_tasks, only: [:index, :show, :new, :create, :destroy] do
      collection do
        get :oss_signature
        get :setup_cors
      end
      member do
        post :execute
      end
    end
    resources :browsers, only: [:index, :show, :new, :create, :edit, :update, :destroy]
    resources :task_logs, only: [:index, :show] do
      collection do
        get :publish_status
      end
    end
    # 任务中心：统一管理/查看（机器端实时 + 本地登记 + 同步/重跑/清除操作 + JSON 监控）
    resources :task_center, only: [:index] do
      collection do
        get  :summary          # JSON 版本（供外部监控 / 钉钉告警）
        get  :machines         # 机器端任务明细列表（机器端 GET /tasks）
        get  :machine_task     # 机器端单个任务详情（机器端 GET /tasks/{id}）
        post :sync
        post :retry_interrupted
        post :clear
        post :resume           # 人工确认启动：调机器端 /tasks/resume 恢复暂停任务
        post :retry_failed     # 批量重新启动失败的任务
      end
    end
    resources :themes, only: [:index, :create, :edit, :update, :destroy] do
      collection do
        get :new_modal
      end
      member do
        get :edit_modal
      end
    end
    resources :post_stats, only: [:index] do
      collection do
        get :export
        get :trends
      end
    end
    resources :account_stats, only: [:index] do
      collection do
        get :export
      end
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
    resources :huasheng_keywords, only: [:index, :show, :new, :create, :edit, :update, :destroy]
    resources :notebooklm_keywords, only: [:index, :show, :new, :create, :edit, :update, :destroy]
    resources :grok_tasks, only: [:index, :show, :new, :create, :edit, :update, :destroy] do
      member do
        post :execute
      end
    end
    resources :heygen_tasks, only: [:index, :show, :new, :create, :edit, :update, :destroy] do
      member do
        post :execute
      end
    end
    resources :warmup_tasks, only: [:index, :show, :new, :create, :destroy] do
      collection do
        get :stats
      end
      member do
        post :execute
      end
    end
    resources :warmup_queue, only: [:index, :show] do
      member do
        post :toggle_warmup
      end
    end
    resources :operation_logs, only: [:index]

    # KOL 自动化触达与管理模块
    resources :kols do
      collection do
        get :import
        get :import_template
        post :import_upload
        post :import_confirm
      end
      member do
        post :activate
        post :deactivate
        post :contact_now
        post :take_over
        post :mark_outcome
        post :mark_auto_reply
        post :add_message
        get :conversation
        post :reply_message
        post :quick_status
      end
    end
    resources :message_templates, except: [:show]
    resources :message_variables, except: [:show] do
      collection do
        get :new_modal
      end
    end
    resources :kol_action_logs, only: [:index]
  end

  namespace :api do
    namespace :v1 do
      # 搬运视频资源接口（录入 / 下载转存 / 剪映处理）
      post "move_videos/import",             to: "move_videos#import"
      get  "move_videos/fetch_for_download", to: "move_videos#fetch_for_download"
      post "move_videos/report_download",    to: "move_videos#report_download"
      get  "move_videos/fetch_for_processing", to: "move_videos#fetch_for_processing"
      get  "move_videos/fetch_pending_process_batch", to: "move_videos#fetch_pending_process_batch"
      post "move_videos/report_processing",  to: "move_videos#report_processing"
      post "move_videos/report_result",      to: "move_videos#report_result"
      post "move_videos/report_merge_result", to: "move_videos#report_merge_result"

      # 搬运混剪接口（认领待混剪源视频 / 回传混剪成品）
      get  "hunjian/fetch_pending", to: "hunjian#fetch_pending"
      post "hunjian/report_result", to: "hunjian#report_result"

      get "task/fetch_next_executable_task", to: "tasks#fetch_next_executable_task"
      get "task/report", to: "tasks#report"
      get "check/accounts"
      get "check/valid_proxies"
      post "check/update_account_status"
      # 发文数据接口
      post "post_stats", to: "post_stats#create"
      post "post_stats/batch", to: "post_stats#batch_create"
      get "post_stats/browsers_with_active_accounts", to: "post_stats#browsers_with_active_accounts"
      # 账号数据接口
      get "accounts", to: "accounts#index"
      get "accounts/:id", to: "accounts#show"
      get "accounts/by_name", to: "accounts#by_name"
      get "accounts/themes", to: "accounts#themes"
      # 账号统计数据批量更新接口（粉丝量/发帖量/发文聚合数据）
      post "account_stats/batch_update", to: "account_stats#batch_update"
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
      post "red_note/batch_add_keywords", to: "red_note#batch_add_keywords"
      # 花生视频储备接口
      get  "huasheng/pending_keywords",    to: "huasheng#pending_keywords"
      get  "huasheng/completed_keywords",  to: "huasheng#completed_keywords"
      post "huasheng/update_status",       to: "huasheng#update_status"
      post "huasheng/report_result",       to: "huasheng#report_result"
      # NotebookLM 视频储备接口
      get  "notebooklm/pending_keywords", to: "notebooklm#pending_keywords"
      post "notebooklm/update_status",    to: "notebooklm#update_status"
      post "notebooklm/report_result",    to: "notebooklm#report_result"
      # 剪映任务批量接收
      post "jianying_tasks/batch", to: "jianying_tasks#batch"
      # 本地视频直传 OSS（返回 PostObject 上传凭证 + 下载签名 URL，客户端直传）
      post "oss/upload_signature", to: "oss#upload_signature"
      # 机器端异步浏览器任务完成回调（养号/发文/采集）
      post "browser_tasks/result", to: "browser_tasks#result"
      # 机器端进程启动上报：立即触发一次「忽略时间窗口」的丢失任务兜底扫描
      post "browser_tasks/machine_restarted", to: "browser_tasks#machine_restarted"
      # 搬运视频按ID范围查询
      get "move_video_queries", to: "move_video_queries#index"
    end
  end

  root to: "admin/dashboard#index"
end