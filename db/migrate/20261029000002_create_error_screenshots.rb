# 任务报错截图表。
#
# 机器端「任何报错都截图」，截图 URL 随回调回传，统一落到本表（覆盖发布/养号/采集/私信/查回复等所有任务类型）。
# 用于按账号 / 任务类型 / 时间 / 错误信息排查。
class CreateErrorScreenshots < ActiveRecord::Migration[6.1]
  def change
    create_table :error_screenshots, comment: '任务报错截图' do |t|
      t.string  :ref,            comment: '业务透传标识（MoveTask:123 / Account:789 等）'
      t.string  :task_type,      comment: '任务类型（nurture/fetch/send_message/check_reply/评论/发布）'
      t.bigint  :account_id,     comment: '账号ID（可空）'
      t.bigint  :browser_id,     comment: '浏览器ID（可空）'
      t.text    :error_msg,      comment: '错误信息'
      t.string  :screenshot_url, comment: '截图 OSS URL'
      t.timestamps
    end

    add_index :error_screenshots, :ref
    add_index :error_screenshots, :task_type
    add_index :error_screenshots, :account_id
    add_index :error_screenshots, :created_at
  end
end
