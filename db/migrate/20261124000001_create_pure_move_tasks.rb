# 纯搬运资源队列表（对应搬运剪映的 move_tasks）。
#
# 一条 pure_move_task = 一个平台的纯搬运发布任务；同一个源视频会按目标平台各建一条。
# 与 move_tasks 的差异：纯搬运跳过剪映/混剪，下载完成（raw_oss_url 已回写）后直接用原视频建发布任务。
class CreatePureMoveTasks < ActiveRecord::Migration[6.1]
  def change
    create_table :pure_move_tasks, comment: '纯搬运资源队列' do |t|
      t.string   :task_uuid,           comment: '任务唯一标识，用于关联日志'
      t.bigint   :move_video_id,       comment: '源视频ID（搬运资源储备 move_videos.id）'
      t.string   :theme,               comment: '内容主题'
      t.text     :title,               comment: '发布标题'
      t.string   :description,         comment: '视频描述'
      t.text     :oss_url,             comment: '源视频 OSS 签名 URL（下载后的原始视频）'
      t.integer  :platform,            comment: '目标发布平台'
      t.integer  :status, default: 0,  comment: '任务状态 pending/waiting_publish/executing/success/failed/claimed'
      t.bigint   :account_id,          comment: '发布账号ID'
      t.bigint   :browser_id,          comment: '执行任务的浏览器ID'
      t.string   :group_id,            comment: '任务组ID（同一源视频的多平台任务共享）'
      t.integer  :failure_count, default: 0, null: false, comment: '发布失败次数，累计达到上限即判定资源不可用并删除'
      t.datetime :start_at,            comment: '任务开始时间'
      t.datetime :actual_publish_time, comment: '实际发布时间'
      t.text     :error_msg,           comment: '错误信息/失败原因'

      t.timestamps
    end

    add_index :pure_move_tasks, :task_uuid, unique: true
    add_index :pure_move_tasks, [:move_video_id, :platform], unique: true
    add_index :pure_move_tasks, :platform
    add_index :pure_move_tasks, :status
    add_index :pure_move_tasks, :theme
    add_index :pure_move_tasks, :group_id
    add_index :pure_move_tasks, :account_id
    add_index :pure_move_tasks, :browser_id
  end
end
