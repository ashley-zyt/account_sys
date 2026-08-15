# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 2026_08_13_000001) do

  create_table "account_stats", charset: "utf8mb4", comment: "账号日维度总量快照（粉丝/浏览/点赞/发帖数）", force: :cascade do |t|
    t.bigint "account_id", null: false, comment: "账号ID"
    t.date "stat_date", null: false, comment: "统计日期（快照所属的自然日）"
    t.integer "followers_count", default: 0, comment: "总粉丝数（截止当前）"
    t.integer "total_views_count", default: 0, comment: "总浏览量（所有发文累计）"
    t.integer "total_likes_count", default: 0, comment: "总点赞量（所有发文累计）"
    t.integer "total_comments_count", default: 0, comment: "总评论量（所有发文累计）"
    t.integer "total_shares_count", default: 0, comment: "总转发量（所有发文累计）"
    t.integer "total_posts_count", default: 0, comment: "总发帖量（截止当前）"
    t.datetime "snapshot_at", comment: "快照采集时间（采集接口返回的时刻）"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["account_id", "stat_date"], name: "index_account_stats_on_account_id_and_stat_date", unique: true
    t.index ["account_id"], name: "index_account_stats_on_account_id"
    t.index ["stat_date"], name: "index_account_stats_on_stat_date"
  end

  create_table "accounts", charset: "utf8mb4", force: :cascade do |t|
    t.integer "platform", default: 1, comment: "平台：facebook/twitter/tiktok/youtube/instagram"
    t.string "account_name", comment: "账号名"
    t.integer "status", default: 0, comment: "账号状态"
    t.string "theme", comment: "账号主题"
    t.integer "work_type", comment: "工作运行方式：搬运/coze/其他"
    t.bigint "browser_id", comment: "绑定的指纹浏览器ID"
    t.string "remark", comment: "备注信息"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.datetime "last_used_at", comment: "最后一次使用时间"
    t.string "source_url", comment: "账号主页链接"
    t.string "operator"
    t.index ["browser_id"], name: "index_accounts_on_browser_id"
    t.index ["last_used_at"], name: "index_accounts_on_last_used_at"
    t.index ["platform"], name: "index_accounts_on_platform"
    t.index ["source_url"], name: "index_accounts_on_source_url"
    t.index ["theme", "status", "last_used_at"], name: "idx_accounts_theme_status_lastused"
  end

  create_table "active_admin_comments", charset: "utf8mb4", force: :cascade do |t|
    t.string "namespace"
    t.text "body"
    t.string "resource_type"
    t.bigint "resource_id"
    t.string "author_type"
    t.bigint "author_id"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["author_type", "author_id"], name: "index_active_admin_comments_on_author"
    t.index ["namespace"], name: "index_active_admin_comments_on_namespace"
    t.index ["resource_type", "resource_id"], name: "index_active_admin_comments_on_resource"
  end

  create_table "admin_users", charset: "utf8mb4", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["email"], name: "index_admin_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_admin_users_on_reset_password_token", unique: true
  end

  create_table "admins", charset: "utf8mb4", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["email"], name: "index_admins_on_email", unique: true
    t.index ["reset_password_token"], name: "index_admins_on_reset_password_token", unique: true
  end

  create_table "browsers", charset: "utf8mb4", force: :cascade do |t|
    t.string "profile_name", comment: "指纹浏览器名称"
    t.string "cloud_id", comment: "指纹浏览器名称ID"
    t.string "proxy_type", comment: "代理类型 http/socks5"
    t.string "proxy_host", comment: "代理IP"
    t.integer "proxy_port", comment: "代理端口"
    t.string "proxy_username", comment: "代理用户名"
    t.string "proxy_password", comment: "代理密码"
    t.integer "status", default: 0, comment: "浏览器状态：online/offline/network_error/busy"
    t.integer "purpose", default: 0, comment: "用途：养号/采集"
    t.string "remark", comment: "备注信息"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "machine_ip", comment: "运营机器IP（该浏览器固定由这台机器运营，避免频繁换IP导致封号）"
    t.index ["machine_ip"], name: "index_browsers_on_machine_ip"
  end

  create_table "conversation_messages", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "conversation_id", null: false, comment: "会话ID"
    t.integer "sender_type", null: false, comment: "发送方类型"
    t.text "content", null: false, comment: "消息内容"
    t.datetime "sent_at", comment: "发送时间"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["conversation_id"], name: "index_conversation_messages_on_conversation_id"
    t.index ["sender_type"], name: "index_conversation_messages_on_sender_type"
    t.index ["sent_at"], name: "index_conversation_messages_on_sent_at"
  end

  create_table "conversations", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "kol_id", null: false, comment: "KOL ID"
    t.bigint "kol_platform_account_id", null: false, comment: "KOL平台账号ID"
    t.bigint "account_id", null: false, comment: "运营账号ID"
    t.integer "platform", null: false, comment: "平台"
    t.integer "status", default: 0, null: false, comment: "会话状态"
    t.datetime "last_message_at", comment: "最后消息时间"
    t.datetime "closed_at", comment: "关闭时间"
    t.text "latest_message", comment: "最新消息摘要"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["account_id"], name: "index_conversations_on_account_id"
    t.index ["kol_id"], name: "index_conversations_on_kol_id"
    t.index ["kol_platform_account_id"], name: "index_conversations_on_kol_platform_account_id"
    t.index ["last_message_at"], name: "index_conversations_on_last_message_at"
    t.index ["platform"], name: "index_conversations_on_platform"
    t.index ["status"], name: "index_conversations_on_status"
  end

  create_table "crypto_videos", charset: "utf8mb4", force: :cascade do |t|
    t.text "global_crypto", comment: "加密货币全球市场数据"
    t.text "global_defi", comment: "全球 DeFi 市场数据"
    t.text "trending", size: :medium, comment: "热门搜索列表"
    t.text "prompt", comment: "提示词"
    t.string "video_id", comment: "视频ID"
    t.string "video_status", comment: "视频生成状态 生成中/已完成"
    t.text "result", comment: "heygen返回的结果"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.integer "heygen_task_id", comment: "Heygen任务ID"
    t.index ["heygen_task_id"], name: "index_crypto_videos_on_heygen_task_id"
    t.index ["video_id"], name: "index_crypto_videos_on_video_id"
    t.index ["video_status"], name: "index_crypto_videos_on_video_status"
  end

  create_table "grok_image_resources", charset: "utf8mb4", force: :cascade do |t|
    t.string "theme"
    t.string "image_url"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "image_name"
    t.index ["theme"], name: "index_grok_image_resources_on_theme"
  end

  create_table "grok_tasks", charset: "utf8mb4", force: :cascade do |t|
    t.string "theme"
    t.string "video_url"
    t.integer "status", default: 0
    t.text "prompt"
    t.bigint "grok_image_id"
    t.bigint "account_id"
    t.text "error_msg"
    t.datetime "start_at"
    t.datetime "actual_publish_time"
    t.bigint "browser_id"
    t.string "task_uuid"
    t.integer "platform"
    t.text "title"
    t.text "description"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["account_id"], name: "index_grok_tasks_on_account_id"
    t.index ["browser_id"], name: "index_grok_tasks_on_browser_id"
    t.index ["grok_image_id"], name: "index_grok_tasks_on_grok_image_id"
    t.index ["status"], name: "index_grok_tasks_on_status"
    t.index ["task_uuid"], name: "index_grok_tasks_on_task_uuid", unique: true
    t.index ["theme"], name: "index_grok_tasks_on_theme"
  end

  create_table "heygen_tasks", charset: "utf8mb4", force: :cascade do |t|
    t.string "theme", comment: "主题"
    t.text "video_url", comment: "视频OSSurl"
    t.integer "status", default: 0, comment: "任务状态 pending/waiting_publish/executing/success/failed"
    t.string "templete_id", comment: "视频模板ID"
    t.text "video_text", comment: "逐字稿"
    t.bigint "account_id", comment: "账号ID"
    t.bigint "browser_id", comment: "浏览器ID"
    t.text "error_msg", comment: "任务结果"
    t.datetime "start_at", comment: "任务开始时间"
    t.datetime "actual_publish_time", comment: "实际发布时间"
    t.string "task_uuid", comment: "任务唯一标识，用于关联日志"
    t.integer "platform", comment: "平台"
    t.text "title", comment: "标题"
    t.text "description", comment: "描述"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["account_id"], name: "index_heygen_tasks_on_account_id"
    t.index ["browser_id"], name: "index_heygen_tasks_on_browser_id"
    t.index ["platform"], name: "index_heygen_tasks_on_platform"
    t.index ["status"], name: "index_heygen_tasks_on_status"
    t.index ["templete_id"], name: "index_heygen_tasks_on_templete_id"
    t.index ["theme"], name: "index_heygen_tasks_on_theme"
  end

  create_table "jianying_tasks", charset: "utf8mb4", force: :cascade do |t|
    t.string "task_uuid", comment: "任务唯一标识，用于关联日志"
    t.text "oss_url", comment: "剪映生成的视频OSS地址"
    t.bigint "account_id", comment: "发布账号ID"
    t.string "theme", comment: "内容主题"
    t.text "title", comment: "发布标题"
    t.integer "status", default: 0, comment: "任务状态 pending/waiting_publish/executing/success/failed"
    t.text "error_msg", comment: "错误信息/失败原因"
    t.datetime "start_at", comment: "任务开始时间"
    t.datetime "actual_publish_time", comment: "实际发布时间"
    t.bigint "browser_id", comment: "执行任务的浏览器ID"
    t.integer "platform", comment: "目标发布平台"
    t.string "group_id", comment: "任务组ID"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "keyword", comment: "关键词"
    t.string "keyword_code", comment: "关键词编码"
    t.text "associated_images", comment: "关联图片（JSON数组）"
    t.string "full_oss_url", comment: "完整OSS视频地址"
    t.string "description", comment: "视频描述"
    t.index ["account_id"], name: "index_jianying_tasks_on_account_id"
    t.index ["browser_id"], name: "index_jianying_tasks_on_browser_id"
    t.index ["group_id"], name: "index_jianying_tasks_on_group_id"
    t.index ["keyword_code"], name: "index_jianying_tasks_on_keyword_code"
    t.index ["platform"], name: "index_jianying_tasks_on_platform"
    t.index ["status"], name: "index_jianying_tasks_on_status"
    t.index ["task_uuid"], name: "index_jianying_tasks_on_task_uuid", unique: true
    t.index ["theme"], name: "index_jianying_tasks_on_theme"
  end

  create_table "kol_platform_accounts", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "kol_id", null: false
    t.integer "platform", null: false, comment: "平台"
    t.string "nick_name", null: false, comment: "平台昵称"
    t.string "profile_url", comment: "主页链接"
    t.string "follower_count", comment: "粉丝数"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["kol_id"], name: "index_kol_platform_accounts_on_kol_id"
    t.index ["nick_name"], name: "index_kol_platform_accounts_on_nick_name"
    t.index ["platform"], name: "index_kol_platform_accounts_on_platform"
  end

  create_table "kols", charset: "utf8mb4", force: :cascade do |t|
    t.string "kol_name", null: false, comment: "KOL名称"
    t.string "nick_name", comment: "昵称"
    t.string "location", comment: "地区"
    t.string "category", comment: "类别"
    t.text "notes", comment: "备注"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["category"], name: "index_kols_on_category"
    t.index ["kol_name"], name: "index_kols_on_kol_name"
  end

  create_table "message_templates", charset: "utf8mb4", force: :cascade do |t|
    t.integer "platform", null: false, comment: "平台"
    t.integer "template_type", null: false, comment: "模板类型"
    t.string "language", default: "en", comment: "语言"
    t.text "content", null: false, comment: "模板内容"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["platform"], name: "index_message_templates_on_platform"
    t.index ["template_type"], name: "index_message_templates_on_template_type"
  end

  create_table "move_tasks", charset: "utf8mb4", force: :cascade do |t|
    t.string "task_uuid", comment: "任务唯一标识，用于关联日志"
    t.bigint "account_id", comment: "发布账号ID"
    t.string "theme", comment: "内容主题"
    t.text "title", comment: "发布标题"
    t.integer "status", default: 0, comment: "任务状态 pending/waiting_publish/executing/success/failed"
    t.text "error_msg", comment: "错误信息/失败原因"
    t.datetime "start_at", comment: "任务开始时间"
    t.datetime "actual_publish_time", comment: "实际发布时间"
    t.bigint "browser_id", comment: "执行任务的浏览器ID"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.integer "platform", comment: "目标发布平台"
    t.string "group_id", comment: "任务组ID，同一视频的多平台任务共享"
    t.bigint "move_video_id"
    t.text "oss_url", comment: "剪映处理后视频 OSS URL（发布用）"
    t.string "description", comment: "视频描述"
    t.index ["browser_id"], name: "index_move_tasks_on_browser_id"
    t.index ["group_id"], name: "index_move_tasks_on_group_id"
    t.index ["move_video_id", "platform"], name: "idx_move_tasks_move_video_platform", unique: true
    t.index ["platform"], name: "index_move_tasks_on_platform"
    t.index ["status", "created_at"], name: "idx_tasks_status_created"
    t.index ["status"], name: "index_move_tasks_on_status"
    t.index ["task_uuid"], name: "index_move_tasks_on_task_uuid", unique: true
    t.index ["theme", "status"], name: "idx_tasks_theme_status"
  end

  create_table "move_videos", charset: "utf8mb4", comment: "搬运视频资源维度表", force: :cascade do |t|
    t.string "source_video_url", null: false, comment: "源视频链接（核心幂等）"
    t.string "source_account_url", comment: "来源账号主页链接"
    t.string "theme", comment: "内容主题"
    t.string "group_id", null: false, comment: "视频组UUID，多平台 move_task 共享"
    t.string "platforms", comment: "目标平台列表，逗号分隔，如 youtube,facebook,twitter,tiktok"
    t.integer "status", default: 0, null: false, comment: "状态 pending_download/downloading/pending_process/processing/processed/failed"
    t.text "raw_oss_url", comment: "下载后原始视频 OSS URL"
    t.text "error_msg", comment: "错误信息/失败原因"
    t.datetime "download_started_at", comment: "下载领取时间"
    t.datetime "downloaded_at", comment: "下载完成时间"
    t.datetime "process_started_at", comment: "剪映领取时间"
    t.datetime "processed_at", comment: "剪映完成时间"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["group_id"], name: "index_move_videos_on_group_id"
    t.index ["source_video_url"], name: "idx_move_videos_source_video_url", unique: true
    t.index ["status", "created_at"], name: "idx_move_videos_status_created"
    t.index ["status"], name: "index_move_videos_on_status"
  end

  create_table "operation_logs", charset: "utf8mb4", force: :cascade do |t|
    t.integer "admin_id", comment: "操作用户ID"
    t.string "admin_name", comment: "操作用户名（冗余存储）"
    t.string "action", comment: "操作类型（create/update/destroy等）"
    t.string "controller", comment: "控制器名称"
    t.string "action_name", comment: "动作名称"
    t.string "target_type", comment: "目标模型类型"
    t.integer "target_id", comment: "目标模型ID"
    t.text "description", comment: "操作描述"
    t.string "ip_address", comment: "操作IP地址"
    t.text "params", comment: "请求参数（JSON格式）"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["admin_id"], name: "index_operation_logs_on_admin_id"
    t.index ["created_at"], name: "index_operation_logs_on_created_at"
    t.index ["target_type", "target_id"], name: "index_operation_logs_on_target_type_and_target_id"
  end

  create_table "operation_tasks", charset: "utf8mb4", force: :cascade do |t|
    t.string "theme", comment: "主题"
    t.text "title", comment: "标题"
    t.text "oss_url", comment: "OSS文件地址"
    t.bigint "account_id", comment: "账号ID"
    t.text "error_msg", comment: "错误信息"
    t.datetime "start_at", comment: "开始时间"
    t.datetime "actual_publish_time", comment: "实际发布时间"
    t.string "browser_id", comment: "浏览器ID"
    t.bigint "group_id", comment: "分组ID"
    t.string "task_uuid", comment: "任务UUID"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.integer "status", default: 0
    t.text "description"
    t.integer "platform"
    t.string "source_filename"
    t.index ["account_id", "oss_url"], name: "index_operation_tasks_on_account_id_and_oss_url", unique: true, length: { oss_url: 255 }
    t.index ["account_id"], name: "index_operation_tasks_on_account_id"
    t.index ["oss_url", "platform"], name: "index_operation_tasks_on_oss_url_and_platform", unique: true, length: { oss_url: 255 }
    t.index ["source_filename"], name: "index_operation_tasks_on_source_filename"
    t.index ["status"], name: "index_operation_tasks_on_status"
    t.index ["task_uuid"], name: "index_operation_tasks_on_task_uuid", unique: true
  end

  create_table "post_stats", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "account_id", null: false, comment: "账号ID"
    t.date "post_date", null: false, comment: "发文日期"
    t.text "title", comment: "发文标题"
    t.text "url", comment: "发文链接"
    t.integer "likes_count", default: 0, comment: "点赞数量"
    t.integer "shares_count", default: 0, comment: "转发数量"
    t.integer "comments_count", default: 0, comment: "评论数量"
    t.integer "views_count", default: 0, comment: "浏览数量"
    t.datetime "data_updated_at", comment: "数据更新时间"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["account_id"], name: "index_post_stats_on_account_id"
    t.index ["post_date"], name: "index_post_stats_on_post_date"
    t.index ["url"], name: "index_post_stats_on_url", unique: true, length: 255
  end

  create_table "red_note_keywords", charset: "utf8mb4", force: :cascade do |t|
    t.string "theme", null: false, comment: "主题"
    t.string "keyword", null: false, comment: "关键词"
    t.string "keyword_code", null: false, comment: "关键词唯一编码"
    t.integer "status", default: 0, comment: "任务状态：0未启动 1待执行 2执行中 3执行完成 4任务失败"
    t.string "task_id", comment: "远程任务ID"
    t.text "result_data", comment: "采集结果数据（JSON）"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.text "image_names", comment: "采集到的图片名称列表（JSON数组）"
    t.index ["keyword_code"], name: "index_red_note_keywords_on_keyword_code", unique: true
    t.index ["status"], name: "index_red_note_keywords_on_status"
    t.index ["theme", "status"], name: "index_red_note_keywords_on_theme_and_status"
    t.index ["theme"], name: "index_red_note_keywords_on_theme"
  end

  create_table "red_note_settings", charset: "utf8mb4", force: :cascade do |t|
    t.integer "search_max_results", default: 20, null: false, comment: "搜索结果前N条帖子"
    t.integer "top_n_by_likes", default: 3, null: false, comment: "前N条帖子里按点赞量排序取前M条"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "task_logs", charset: "utf8mb4", force: :cascade do |t|
    t.string "task_uuid", comment: "关联的任务UUID"
    t.text "request_data", comment: "请求参数/发送内容"
    t.text "response_data", comment: "接口返回数据"
    t.integer "status", default: 0, comment: "执行结果 success/failed"
    t.text "error_msg", comment: "执行错误信息"
    t.datetime "run_at", comment: "执行时间"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.bigint "account_id", comment: "执行账号ID快照（任务释放后仍保留关联）"
    t.string "browser_id", comment: "执行浏览器ID快照（任务释放后仍保留关联）"
    t.index ["account_id"], name: "index_task_logs_on_account_id"
    t.index ["browser_id"], name: "index_task_logs_on_browser_id"
    t.index ["run_at"], name: "index_task_logs_on_run_at"
    t.index ["status"], name: "index_task_logs_on_status"
    t.index ["task_uuid"], name: "index_task_logs_on_task_uuid"
  end

  create_table "themes", charset: "utf8mb4", force: :cascade do |t|
    t.string "name", null: false
    t.string "oss_directory"
    t.text "titles"
    t.text "remark"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.text "prompts"
    t.index ["name"], name: "index_themes_on_name", unique: true
    t.index ["oss_directory"], name: "index_themes_on_oss_directory", unique: true
  end

  create_table "warmup_profiles", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "last_warmup_at"
    t.boolean "warmup_enabled", default: true
    t.string "warmup_frequency", default: "weekly"
    t.string "warmup_status"
    t.integer "warmup_batch", default: 0
    t.string "machine"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["account_id"], name: "index_warmup_profiles_on_account_id"
    t.index ["machine"], name: "index_warmup_profiles_on_machine"
    t.index ["warmup_batch"], name: "index_warmup_profiles_on_warmup_batch"
    t.index ["warmup_enabled"], name: "index_warmup_profiles_on_warmup_enabled"
  end

  create_table "warmup_tasks", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "browser_id"
    t.integer "platform", null: false
    t.text "operations"
    t.integer "status", default: 0
    t.text "error_msg"
    t.datetime "executed_at"
    t.string "task_uuid"
    t.integer "duration_minutes"
    t.string "machine"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["account_id", "status"], name: "index_warmup_tasks_on_account_id_and_status"
    t.index ["account_id"], name: "index_warmup_tasks_on_account_id"
    t.index ["browser_id"], name: "index_warmup_tasks_on_browser_id"
    t.index ["executed_at"], name: "index_warmup_tasks_on_executed_at"
    t.index ["machine"], name: "index_warmup_tasks_on_machine"
    t.index ["platform"], name: "index_warmup_tasks_on_platform"
    t.index ["task_uuid"], name: "index_warmup_tasks_on_task_uuid"
  end

  add_foreign_key "conversation_messages", "conversations"
  add_foreign_key "kol_platform_accounts", "kols"
  add_foreign_key "warmup_profiles", "accounts"
  add_foreign_key "warmup_tasks", "accounts"
  add_foreign_key "warmup_tasks", "browsers"
end
