# 搬运混剪资源队列表（对应搬运剪映的 move_tasks）。
#
# 一条 hunjian_task = 一个平台的混剪发布任务；同一个混剪成品会按目标平台各建一条。
# 与 move_tasks 的差异：混剪是「2 个源视频 → 1 个成品」，故用 move_video_ids（逗号分隔）
# 记录参与混剪的多个源视频 id，而非单一 move_video_id。
class CreateHunjianTasks < ActiveRecord::Migration[6.1]
  def change
    create_table :hunjian_tasks, comment: '搬运混剪资源队列' do |t|
      t.string   :task_uuid,     comment: '任务唯一标识，用于关联日志'
      t.string   :move_video_ids, comment: '源视频ID（逗号分隔，混剪为2个）'
      t.string   :theme,         comment: '内容主题'
      t.text     :title,         comment: '发布标题'
      t.string   :description,   comment: '视频描述'
      t.text     :oss_url,       comment: '混剪成品 OSS 签名 URL'
      t.text     :full_oss_url,  comment: '混剪成品 OSS object key'
      t.integer  :platform,      comment: '目标发布平台'
      t.integer  :status, default: 0, comment: '任务状态 pending/waiting_publish/executing/success/failed'
      t.bigint   :account_id,    comment: '发布账号ID'
      t.bigint   :browser_id,    comment: '执行任务的浏览器ID'
      t.string   :group_id,      comment: '任务组ID（同一混剪成品的多平台任务共享）'
      t.datetime :start_at,      comment: '任务开始时间'
      t.datetime :actual_publish_time, comment: '实际发布时间'
      t.text     :error_msg,     comment: '错误信息/失败原因'

      t.timestamps
    end

    add_index :hunjian_tasks, :task_uuid, unique: true
    add_index :hunjian_tasks, :platform
    add_index :hunjian_tasks, :status
    add_index :hunjian_tasks, :theme
    add_index :hunjian_tasks, :group_id
    add_index :hunjian_tasks, :account_id
    add_index :hunjian_tasks, :browser_id
  end
end
