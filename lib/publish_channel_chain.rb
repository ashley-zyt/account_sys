# 发布渠道优先级链：决定账号发布时按什么顺序尝试渠道。
#
# 语义：
#   - 平台默认链（未指定首选渠道时）：
#     twitter → 浏览器 × 2 → x_api
#     其它    → 浏览器 × 2 → postforme → postpeer
#   - 账号「首选渠道」（accounts.publish_channel）非空时，只用该渠道，不回退
#   - 某渠道不可用（无浏览器机器 / 无对应授权）时自动跳过
#
# 回退游标用任务上的 failure_count：失败 +1，下一次用 available_chain[failure_count]，
# 取到 nil 表示所有可用渠道都已尝试过，任务终态失败。
module PublishChannelChain
  # 平台默认链（未指定首选渠道时）：
  #   - twitter：浏览器 × 2 → x_api（postpeer 不发 X，不参与）
  #   - 其它：浏览器 × 2 → postforme → postpeer（postpeer 作为最后一层保底）
  def self.default_chain(platform)
    if platform.to_s == 'twitter'
      ['ag_center', 'ag_center', 'x_api']
    else
      ['ag_center', 'ag_center', 'postforme', 'postpeer']
    end
  end

  # 账号完整链：指定了首选渠道就只用该渠道；否则走平台默认链。
  def self.for_account(account)
    preferred = account.publish_channel
    return [preferred] if preferred.present?
    default_chain(account.platform)
  end

  # 某渠道当前是否可用（该账号是否具备该渠道的授权/机器）
  def self.available?(account, channel)
    case channel
    when 'ag_center'
      account.browser.present? && account.browser.machine_ip.present?
    when 'x_api'
      account.x_credential&.authorized?
    when 'postforme'
      account.postforme_account&.authorized?
    when 'postpeer'
      account.platform.to_s != 'twitter' && account.postpeer_account&.authorized?
    else
      false
    end
  end

  # 账号可用渠道链（完整链里过滤掉不可用的）
  def self.available_chain(account)
    for_account(account).select { |c| available?(account, c) }
  end

  # 按失败次数取「下一次该用的渠道」；返回 nil 表示所有可用渠道都已试过
  def self.channel_at(account, failure_count)
    available_chain(account)[failure_count.to_i]
  end
end
