# 发布渠道优先级链：决定账号发布时按什么顺序尝试渠道。
#
# 语义：
#   - 平台默认链：浏览器(ag_center) × 2 → API（Twitter→x_api，其它→postforme）
#     （浏览器模拟对视频格式较敏感，给两次机会；两次都失败才切已授权的 API 渠道）
#   - 账号「首选渠道」（accounts.publish_channel）非空时跳到最前，其余照默认链顺序
#   - 某渠道不可用（无浏览器机器 / 无对应授权）时自动跳过
#   - 新渠道确定后，在 default_chain 里插入即可
#
# 回退游标用任务上的 failure_count：失败 +1，下一次用 available_chain[failure_count]，
# 取到 nil 表示所有可用渠道都已尝试过，任务终态失败。
module PublishChannelChain
  # 各平台的 API 渠道：Twitter→x_api，其它→postforme
  def self.api_channel(platform)
    platform.to_s == 'twitter' ? 'x_api' : 'postforme'
  end

  # 平台默认链：浏览器 × 2 → API
  def self.default_chain(platform)
    ['ag_center', 'ag_center', api_channel(platform)]
  end

  # 从列表里移除「首个」等于 item 的元素（保留后续重复项）。
  # 用于首选渠道与默认链合并时：浏览器作为首选渠道时，默认链里仍保留一次浏览器重试。
  def self.remove_first(list, item)
    idx = list.index(item)
    return list.dup unless idx
    list.dup.tap { |l| l.delete_at(idx) }
  end

  # 账号完整链：首选渠道(非空) + 默认链(去重一次)
  def self.for_account(account)
    preferred = account.publish_channel
    base = default_chain(account.platform)
    return base if preferred.blank?
    [preferred] + remove_first(base, preferred)
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
