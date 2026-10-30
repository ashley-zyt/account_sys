# == Schema Information
#
# Table name: account_change_logs
#
#  id                                                                   :bigint           not null, primary key
#  abnormal_type(异常类型 0封禁/限制 1未登录 2网络 3其他（仅系统自动）) :integer
#  change_reason(变更原因)                                              :string(255)
#  change_source(变更来源 0系统自动 1人工)                              :integer          not null
#  changed_at(变更/发现时间)                                            :datetime
#  changes_json(字段级变更明细 [{field, from, to}])                     :text(65535)
#  error_msg(完整错误信息)                                              :text(65535)
#  matched_keyword(命中的关键词)                                        :string(255)
#  operator(更改人/操作人（人工）)                                      :string(255)
#  screenshot_url(截图 OSS URL)                                         :string(255)
#  source_action(发现动作：发布/采集/私信/养号/登录检查)                :string(255)
#  created_at                                                           :datetime         not null
#  updated_at                                                           :datetime         not null
#  account_id(账号ID)                                                   :bigint           not null
#
# Indexes
#
#  index_account_change_logs_on_abnormal_type  (abnormal_type)
#  index_account_change_logs_on_account_id     (account_id)
#  index_account_change_logs_on_change_source  (change_source)
#  index_account_change_logs_on_changed_at     (changed_at)
#
class AccountChangeLog < ApplicationRecord
  belongs_to :account, optional: true

  # 变更来源
  enum change_source: {
    system: 0,   # 系统自动（机器端检测到异常）
    manual: 1    # 人工操作
  }

  # 异常类型（仅系统自动时填；人工为 null）
  enum abnormal_type: {
    banned: 0,      # 封禁/限制
    logged_out: 1,  # 未登录
    network: 2,     # 网络（代理失效等）
    other: 3        # 其他（人机验证等）
  }

  # 记录一条账号变更/异常（旁路日志，失败不影响主流程）
  # @param changes [Array<Hash>] [{ field:, from:, to: }]
  def self.record!(account:, change_source:, changes:, abnormal_type: nil, operator: nil,
                   change_reason: nil, source_action: nil, matched_keyword: nil,
                   error_msg: nil, screenshot_url: nil, changed_at: Time.current)
    return nil if account.nil?

    create!(
      account_id: account.id,
      change_source: change_source,
      abnormal_type: abnormal_type,
      operator: operator,
      change_reason: change_reason,
      changes_json: Array(changes).to_json,
      source_action: source_action,
      matched_keyword: matched_keyword,
      error_msg: error_msg,
      screenshot_url: screenshot_url,
      changed_at: changed_at
    )
  rescue => e
    Rails.logger.error "[AccountChangeLog] 记录失败 account=#{account&.id}: #{e.message}"
    nil
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[id account_id change_source abnormal_type operator change_reason source_action matched_keyword error_msg changed_at created_at updated_at]
  end

  # 解析 changes_json 为数组
  def changes_array
    JSON.parse(changes_json.to_s)
  rescue JSON::ParserError
    []
  end

  # 变更明细可读文本，如「状态: 正常 → 未登录」
  def changes_text
    changes_array.map do |c|
      field = c['field'].to_s
      from = c['from'].to_s
      to = c['to'].to_s
      from.blank? ? "#{field}: #{to}" : "#{field}: #{from} → #{to}"
    end.join('；')
  end

  def change_source_label
    system? ? '系统自动' : '人工'
  end

  def abnormal_type_label
    return '-' if abnormal_type.nil?
    case abnormal_type
    when 'banned' then '封禁/限制'
    when 'logged_out' then '未登录'
    when 'network' then '网络'
    when 'other' then '其他'
    else abnormal_type
    end
  end

  def self.ransackable_associations(auth_object = nil)
    %w[account]
  end
end
