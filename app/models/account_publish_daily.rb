# == Schema Information
#
# Table name: account_publish_dailies
#
#  id                                                                                        :bigint           not null, primary key
#  error_msg(失败时的具体错误信息)                                                           :text(65535)
#  platform(平台快照（accounts.platform 枚举值）)                                            :integer
#  reason(未发布/失败原因文本)                                                               :string(255)
#  result(发布结果 0成功 1失败 2agent 3封禁 4tiktok低浏览 5资源不足 6无浏览器 7有资源未发布) :integer          not null
#  source(记录来源 0当场记录 1反推兜底)                                                      :integer          default("backfill"), not null
#  stat_date(统计日期)                                                                       :date             not null
#  theme(主题快照)                                                                           :string(255)
#  work_type(工作模式快照（中文名）)                                                         :string(255)
#  created_at                                                                                :datetime         not null
#  updated_at                                                                                :datetime         not null
#  account_id(账号ID)                                                                        :bigint           not null
#  task_log_id(关联当天该账号的 task_log（可空）)                                            :bigint
#
# Indexes
#
#  index_account_publish_dailies_on_account_id                (account_id)
#  index_account_publish_dailies_on_stat_date_and_account_id  (stat_date,account_id) UNIQUE
#  index_account_publish_dailies_on_stat_date_and_platform    (stat_date,platform)
#  index_account_publish_dailies_on_stat_date_and_result      (stat_date,result)
#  index_account_publish_dailies_on_stat_date_and_source      (stat_date,source)
#
class AccountPublishDaily < ApplicationRecord
  belongs_to :account, optional: true

  # 发布结果枚举
  enum result: {
    success: 0,            # 发布成功
    failed: 1,             # 发布失败
    agent: 2,              # agent 外部发布（系统不发布，正常）
    banned: 3,             # 账号封禁/停用/未登录
    tiktok_low_views: 4,   # TikTok 近3天0浏览量跳过
    no_resource: 5,        # 资源不足（无 pending）
    no_browser: 6,         # 未绑定浏览器/无 machine_ip
    unpublished: 7         # 有资源未发布（含无资源队列模式，待核查）
  }

  # 记录来源：区分「发布链路当场记录」与「事后反推兜底」，方便核对数据准确性
  enum source: {
    realtime: 0,           # 当场记录（发布链路实时写）
    backfill: 1            # 反推兜底（backfill!/build_for 事后 classify）
  }

  def self.ransackable_attributes(auth_object = nil)
    %w[id stat_date account_id platform theme work_type result source reason error_msg created_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[account]
  end

  # ---- 每日对账计算 ----

  # 当场记录单个账号某天的发布结果（覆盖式：同一天同账号后写覆盖先写）。
  # 供发布链路各节点在「事件发生的当下」调用，避免事后反推时资源/状态已变化导致误差。
  # @param account [Account] 账号对象
  # @param result [Symbol, String] 见 result 枚举
  # @param reason [String] 结果原因文案
  # @param date [Date] 归属统计日期，默认今天
  def self.record!(account, result:, reason:, error_msg: nil, task_log_id: nil, date: Date.today)
    return nil if account.nil?

    record = find_or_initialize_by(stat_date: date, account_id: account.id)
    record.update!(
      platform:    Account.platforms[account.platform],
      theme:       account.theme,
      work_type:   account.work_type,
      result:      result,
      reason:      reason,
      error_msg:   error_msg,
      task_log_id: task_log_id,
      source:      :realtime
    )
    record
  rescue => e
    # 对账记录是「旁路」数据，绝不能因写对账失败而阻断发布主流程
    Rails.logger.error "[AccountPublishDaily] 当场记录失败 account=#{account&.id} result=#{result}: #{e.message}"
    nil
  end

  # 发布结果当场记录（success/failed）：供发布日志落库处复用，把「发布日志」同步成对账结果。
  # @param account_id [Integer, nil] 执行账号快照 ID（拿不到则跳过，不写对账）
  def self.record_publish_result!(account_id, status, error_msg: nil, task_log_id: nil, date: Date.today)
    return nil if account_id.blank?

    account = Account.unscoped.find_by(id: account_id)
    return nil unless account

    succeeded = status.to_s == 'success'
    record!(
      account,
      result:      succeeded ? :success : :failed,
      reason:      succeeded ? '发布成功' : (error_msg.presence || '发布失败'),
      error_msg:   error_msg,
      task_log_id: task_log_id,
      date:        date
    )
  end

  # 兜底补缺：只对「date 当天还没有对账记录」的账号跑 classify 补上原因。
  # 与 build_for（全量 upsert）不同，这里绝不覆盖当天已由发布链路「当场记录」的准确结果，
  # 只补那些没被记录到的漏网账号（agent / 无浏览器 / 有资源未发 / 未轮到分配等静态或边缘原因）。
  # @return [Integer] 补缺的账号条数
  def self.backfill!(date = Date.today)
    day_start = date.beginning_of_day
    day_end   = date.end_of_day

    recorded_ids = where(stat_date: date).pluck(:account_id)

    last_log_by_account = {}
    TaskLog.where(run_at: day_start..day_end)
           .where.not(account_id: nil)
           .order(:run_at, :id)
           .pluck(:account_id, :status, :error_msg, :id)
           .each do |account_id, status, error_msg, id|
             last_log_by_account[account_id] = { status: status, error_msg: error_msg, id: id }
           end

    count = 0
    scope = Account.unscoped.where(deleted_at: nil)
    scope = scope.where.not(id: recorded_ids) if recorded_ids.any?
    scope.find_each do |account|
      begin
        result, reason, error_msg, task_log_id = classify(account, last_log_by_account[account.id])
        create!(
          stat_date:   date,
          account_id:  account.id,
          platform:    Account.platforms[account.platform],
          theme:       account.theme,
          work_type:   account.work_type,
          result:      result,
          reason:      reason,
          error_msg:   error_msg,
          task_log_id: task_log_id,
          source:      :backfill
        )
        count += 1
      rescue ActiveRecord::RecordNotUnique
        next
      rescue => e
        Rails.logger.error "[AccountPublishDaily] 兜底补缺失败 account=#{account.id}: #{e.message}"
      end
    end
    count
  end

  # 生成某天的对账快照（幂等：按 stat_date+account_id upsert，可重复跑）
  # @param date [Date] 统计日期，默认今天
  # @return [Integer] 落库的账号条数
  def self.build_for(date = Date.today)
    day_start = date.beginning_of_day
    day_end   = date.end_of_day

    # 一次性加载当天所有发布日志，按账号取最后一条（run_at 最大）
    last_log_by_account = {}
    TaskLog.where(run_at: day_start..day_end)
           .where.not(account_id: nil)
           .order(:run_at, :id)
           .pluck(:account_id, :status, :error_msg, :id)
           .each do |account_id, status, error_msg, id|
             last_log_by_account[account_id] = { status: status, error_msg: error_msg, id: id }
           end

    count = 0
    Account.unscoped.where(deleted_at: nil).find_each do |account|
      result, reason, error_msg, task_log_id = classify(account, last_log_by_account[account.id])

      record = find_or_initialize_by(stat_date: date, account_id: account.id)
      record.update!(
        platform:    Account.platforms[account.platform],
        theme:       account.theme,
        work_type:   account.work_type,
        result:      result,
        reason:      reason,
        error_msg:   error_msg,
        task_log_id: task_log_id,
        source:      :backfill
      )
      count += 1
    end
    count
  end

  # 判定单个账号当天的结果
  # @return [Array] [result_key, reason, error_msg, task_log_id]
  def self.classify(account, last_log)
    # 账号状态异常（封禁/停用/未登录）：优先看当天是否有日志（可能发布失败后才封禁）
    unless account.status == '正常'
      if last_log
        if last_log[:status] == 'success'
          return ['success', "发布成功（后账号#{account.status}）", nil, last_log[:id]]
        else
          msg = last_log[:error_msg].presence || '发布失败'
          return ['failed', "发布失败后#{account.status}：#{msg}", msg, last_log[:id]]
        end
      end
      return ['banned', "账号#{account.status}", nil, nil]
    end

    # 正常账号：有日志看结果
    if last_log
      if last_log[:status] == 'success'
        return ['success', '发布成功', nil, last_log[:id]]
      else
        msg = last_log[:error_msg].presence || '发布失败'
        return ['failed', msg, msg, last_log[:id]]
      end
    end

    # 无日志：逐项判断未发布原因
    return ['agent', 'agent 外部发布（系统不发布）', nil, nil] if account.work_type.to_s == 'agent'

    return ['tiktok_low_views', 'TikTok 近3天0浏览量，跳过分配', nil, nil] if account.platform.to_s == 'tiktok' && account.zero_views_in_past_3_days?

    return ['no_browser', '未绑定浏览器或无 machine_ip', nil, nil] if account.browser.blank? || account.browser.machine_ip.blank?

    model = account.task_model_for_work_type
    return ['unpublished', '无资源队列模式', nil, nil] if model.nil?

    pending = model.where(theme: account.theme, platform: account.platform, status: :pending).count
    return ['no_resource', '资源不足（无 pending 资源）', nil, nil] if pending.zero?

    ['unpublished', '有资源未发布（待核查）', nil, nil]
  end
end
