# 发布渠道优先级链：决定账号发布时按什么顺序尝试渠道。
#
# 语义：
#   - 平台默认链（未指定首选渠道时）：
#     twitter → 浏览器 × 2 → x_api
#     其它    → 浏览器 × 2 → postforme → postpeer
#   - 账号「首选渠道」为 API 渠道（postforme/x_api/postpeer）时，只用该渠道，不回退；
  #     ag_center（浏览器）或未指定时走平台默认链
#   - 某渠道不可用（无浏览器机器 / 无对应授权）时自动跳过
#
# 回退游标用任务上的 failure_count：失败 +1，下一次用 available_chain[failure_count]，
# 取到 nil 表示所有可用渠道都已尝试过，任务终态失败。
module PublishChannelChain
  # 平台 × 媒体形态 → 支持渠道 矩阵。
  #
  # 用于发布时按任务的媒体形态过滤渠道链：某形态下不支持的渠道会被跳过，
  # 避免「浏览器不支持图文却先试浏览器」这类无效回退。
  #
  # - 未声明某平台/形态 = 不限制（沿用默认链，行为与历史一致，即只发视频的场景）
  # - 未来浏览器支持图文后，只需在对应形态列表里加回 'ag_center' 即可
  CHANNEL_MEDIA_SUPPORT = {
    'twitter' => {
      'video' => %w[ag_center x_api],
      'image' => %w[x_api],   # 浏览器暂不支持图文，先只走 X API
      'text'  => %w[x_api]    # 纯文字同理
    }
  }.freeze

  # 某平台在某媒体形态下是否声明了渠道限制
  def self.media_support_declared?(platform, media_type)
    return false if platform.blank? || media_type.blank?
    CHANNEL_MEDIA_SUPPORT.dig(platform.to_s, media_type.to_s).present?
  end

  # 某平台在某媒体形态下，某渠道是否可用（未声明则视为可用，不限制）
  def self.channel_supports_media?(platform, media_type, channel)
    return true unless media_support_declared?(platform, media_type)
    CHANNEL_MEDIA_SUPPORT.dig(platform.to_s, media_type.to_s).include?(channel)
  end

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

  # 账号完整链：显式指定 API 渠道（postforme/x_api/postpeer）才用唯一渠道，不回退；
  # 指定 ag_center（浏览器）或未指定时，走平台默认链（浏览器 × 2 → API）。
  def self.for_account(account)
    preferred = account.publish_channel
    return [preferred] if preferred.present? && preferred.to_s != 'ag_center'
    default_chain(account.platform)
  end

  # 某渠道当前是否可用（该账号是否具备该渠道的授权/机器）
  def self.available?(account, channel)
    case channel
    when 'ag_center'
      # 云手机浏览器不下发浏览器模拟发布，自动跳过走 API 渠道
      account.browser.present? && account.browser.machine_host.present? && !account.browser.cloud_phone?
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

  # 账号可用渠道链（完整链里过滤掉不可用的渠道，再按媒体形态过滤不支持的渠道）。
  # @param media_type [String, nil] 媒体形态（video/image/text）；nil 表示不限制（历史行为）
  def self.available_chain(account, media_type: nil)
    chain = for_account(account).select { |c| available?(account, c) }
    if media_type.present?
      chain = chain.select { |c| channel_supports_media?(account.platform, media_type, c) }
    end
    chain
  end

  # 按失败次数取「下一次该用的渠道」；返回 nil 表示所有可用渠道都已试过
  def self.channel_at(account, failure_count, media_type: nil)
    available_chain(account, media_type: media_type)[failure_count.to_i]
  end
end
