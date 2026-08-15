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

ActiveRecord::Schema[7.0].define(version: 2026_02_13_154539) do
  create_table "accounts", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.integer "platform", default: 1, comment: "平台：facebook/twitter/tiktok/youtube/instagram"
    t.string "account_name", comment: "账号名"
    t.integer "status", default: 0, comment: "账号状态"
    t.string "theme", comment: "账号主题"
    t.integer "work_type", comment: "工作运行方式：搬运/coze/其他"
    t.bigint "browser_id", comment: "绑定的指纹浏览器ID"
    t.string "remark", comment: "备注信息"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "last_used_at", precision: nil, comment: "最后一次使用时间"
    t.index ["browser_id"], name: "index_accounts_on_browser_id"
    t.index ["last_used_at"], name: "index_accounts_on_last_used_at"
    t.index ["platform"], name: "index_accounts_on_platform"
    t.index ["theme", "status", "last_used_at"], name: "idx_accounts_theme_status_lastused"
  end

  create_table "active_admin_comments", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "namespace"
    t.text "body"
    t.string "resource_type"
    t.bigint "resource_id"
    t.string "author_type"
    t.bigint "author_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["author_type", "author_id"], name: "index_active_admin_comments_on_author"
    t.index ["namespace"], name: "index_active_admin_comments_on_namespace"
    t.index ["resource_type", "resource_id"], name: "index_active_admin_comments_on_resource"
  end

  create_table "admin_users", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_admin_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_admin_users_on_reset_password_token", unique: true
  end

  create_table "admins", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_admins_on_email", unique: true
    t.index ["reset_password_token"], name: "index_admins_on_reset_password_token", unique: true
  end

  create_table "browsers", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
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
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "move_tasks", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "task_uuid", comment: "任务唯一标识，用于关联日志"
    t.string "video_url", comment: "源视频地址"
    t.string "source_account_url", comment: "来源账号主页链接"
    t.bigint "account_id", comment: "发布账号ID"
    t.string "theme", comment: "内容主题"
    t.text "title", comment: "发布标题"
    t.integer "status", default: 0, comment: "任务状态 pending/waiting_publish/executing/success/failed"
    t.text "error_msg", comment: "错误信息/失败原因"
    t.datetime "start_at", precision: nil, comment: "任务开始时间"
    t.datetime "actual_publish_time", precision: nil, comment: "实际发布时间"
    t.bigint "browser_id", comment: "执行任务的浏览器ID"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "platform", comment: "目标发布平台"
    t.string "group_id", comment: "任务组ID，同一视频的多平台任务共享"
    t.index ["browser_id"], name: "index_move_tasks_on_browser_id"
    t.index ["group_id"], name: "index_move_tasks_on_group_id"
    t.index ["platform"], name: "index_move_tasks_on_platform"
    t.index ["status", "created_at"], name: "idx_tasks_status_created"
    t.index ["status"], name: "index_move_tasks_on_status"
    t.index ["task_uuid"], name: "index_move_tasks_on_task_uuid", unique: true
    t.index ["theme", "status"], name: "idx_tasks_theme_status"
    t.index ["video_url", "platform"], name: "idx_move_tasks_video_platform", unique: true
  end

  create_table "task_logs", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "task_uuid", comment: "关联的任务UUID"
    t.text "request_data", comment: "请求参数/发送内容"
    t.text "response_data", comment: "接口返回数据"
    t.integer "status", default: 0, comment: "执行结果 success/failed"
    t.text "error_msg", comment: "执行错误信息"
    t.datetime "run_at", precision: nil, comment: "执行时间"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["run_at"], name: "index_task_logs_on_run_at"
    t.index ["status"], name: "index_task_logs_on_status"
    t.index ["task_uuid"], name: "index_task_logs_on_task_uuid"
  end

end
