# == Schema Information
#
# Table name: task_assignments
#
#  id                                                                       :bigint           not null, primary key
#  assigned_at(本次发活时间)                                                :datetime
#  release_reason(释放原因)                                                 :string(255)
#  released_at(本次归属被释放的时间（重置/中断/失败回退时写入）)            :datetime
#  task_type(工作模式 key（move/operation/jianying/grok/heygen），便于排查) :string(255)
#  task_uuid(资源队列任务的 task_uuid（与 task_logs 同一关联方式）)         :string(255)      not null
#  created_at                                                               :datetime         not null
#  updated_at                                                               :datetime         not null
#  account_id(发活时分配的账号（任务释放后仍保留）)                         :bigint
#  browser_id(发活时分配的浏览器（任务释放后仍保留）)                       :string(255)
#
# Indexes
#
#  index_task_assignments_on_account_id            (account_id)
#  index_task_assignments_on_assigned_at           (assigned_at)
#  index_task_assignments_on_browser_id            (browser_id)
#  index_task_assignments_on_task_uuid             (task_uuid)
#  index_task_assignments_on_uuid_and_released_at  (task_uuid,released_at)
#
# == 任务「发活」时的账号/浏览器归属快照
#
# 为什么需要它（2026-09-22 排查结论）：
#   资源队列任务的 account_id / browser_id 在「释放」时会被清空（重置回 pending、被超时兜底重置、
#   失败回退、批量回退等），而回调是异步的、常常晚于释放。若在回调落 task_logs 时才去读任务上的归属：
#     · 已释放且未被重派 → 读到 nil   → 日志对不上账号/浏览器（最常见的现象）
#     · 已释放且已被重派 → 读到新账号 → 日志张冠李戴（更危险）
#   所以在「发活」那一刻就把归属固化到本表，释放时只标 released_at、绝不删记录，回调时优先用这份快照。
#
# 关联方式与 task_logs 一致（按 task_uuid），因此一处覆盖 move/operation/jianying/grok/heygen 全部模式。
#
# 注意（诚实边界）：一个 task_uuid 若出现「释放 → 重新分配 → 旧回调才到」，本表无法区分是哪一次执行
# 的回调（回调里没有执行代次标识），此时只能取「当前生效的归属」，仍可能记成新账号。
# 要彻底杜绝需要回调携带 execution_id（见「按批恢复暂停任务方案.md」同期的方案 B）。
class TaskAssignment < ApplicationRecord
  belongs_to :account, optional: true

  scope :for_task,   ->(uuid) { where(task_uuid: uuid.to_s) }
  scope :unreleased, -> { where(released_at: nil) }
  scope :latest,     -> { order(assigned_at: :desc, id: :desc) }

  class << self
    # 发活时记录归属（在「分配账号/浏览器」成功后调用）
    # 刻意不抛异常：记录归属失败不应阻断发活主流程，只在日志里留痕。
    # @return [TaskAssignment, nil]
    def record!(task)
      return nil if task.nil? || task.task_uuid.blank?

      create!(
        task_uuid:   task.task_uuid,
        task_type:   work_mode_key(task),
        account_id:  task.account_id,
        browser_id:  task.browser_id&.to_s,
        assigned_at: Time.current
      )
    rescue => e
      Rails.logger.error "[TaskAssignment] 记录发活归属失败 #{task.class}##{task.id}: #{e.class} #{e.message}"
      nil
    end

    # 释放归属：把当前「未释放」的那条标掉。
    # 不删除 —— 迟到的回调还要靠它认人，这正是本表存在的理由。
    # @return [Integer] 受影响条数
    def release!(task_uuid, reason = nil)
      return 0 if task_uuid.blank?

      for_task(task_uuid).unreleased.update_all(
        released_at:    Time.current,
        release_reason: reason,
        updated_at:     Time.current
      )
    end

    # 批量释放（按 task_uuid 列表）
    def release_many!(task_uuids, reason = nil)
      uuids = Array(task_uuids).compact.reject(&:blank?).map(&:to_s).uniq
      return 0 if uuids.empty?

      where(task_uuid: uuids).unreleased.update_all(
        released_at:    Time.current,
        release_reason: reason,
        updated_at:     Time.current
      )
    end

    # 回调落日志时取归属快照：
    #   优先「仍未释放的那条」（当前生效的归属）；
    #   没有则退回「最近一条已释放的」—— 迟到回调正是本表要救的场景。
    # @return [TaskAssignment, nil]
    def snapshot_for(task_uuid)
      return nil if task_uuid.blank?

      scope = for_task(task_uuid)
      scope.unreleased.latest.first || scope.latest.first
    end

    # 工作模式 key（move/operation/jianying/grok/heygen），仅用于排查展示
    def work_mode_key(task)
      mode = WorkMode.for_model(task.class)
      mode&.key || task.class.name.underscore.sub(/_task\z/, '')
    rescue => e
      nil
    end
  end
end
