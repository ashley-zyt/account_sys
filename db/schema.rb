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

ActiveRecord::Schema.define(version: 2026_08_15_000001) do

  create_table "huasheng_keywords", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "theme", null: false, comment: "主题"
    t.string "keyword", null: false, comment: "关键词"
    t.integer "status", default: 0, comment: "任务状态：0未启动 1待执行 2执行中 3执行完成 4任务失败"
    t.string "task_id", comment: "远程任务ID"
    t.text "result_data", comment: "采集结果数据（JSON）"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["status"], name: "index_huasheng_keywords_on_status"
    t.index ["theme", "status"], name: "index_huasheng_keywords_on_theme_and_status"
    t.index ["theme"], name: "index_huasheng_keywords_on_theme"
  end

end
