# == Schema Information
#
# Table name: kol_contacts
#
#  id                                                                                                                     :bigint           not null, primary key
#  dm_blocked_reason(对方不可私信原因（人工标记）0=仅关注者可私信 1=需要验证账号 2=关闭私信 3=账号被暂停 4=@username失效) :integer
#  last_sent_at(最后发送成功时间（回复轮询频率衰减的基准）)                                                               :datetime
#  last_used_at(最后使用时间)                                                                                             :datetime
#  messaging_enabled(是否可作为发信渠道)                                                                                  :boolean          default(FALSE), not null
#  monitor_until(回复监测截止时间（该联系方式最后一次发送成功时间 + 30 天）)                                              :datetime
#  next_poll_at(下次回复轮询时间（按发送成功后衰减频率计算）)                                                             :datetime
#  nickname(平台昵称/账号)                                                                                                :string(255)
#  outreach_channel(触达方式 0=指纹浏览器 1=X认证（默认 X认证）)                                                          :integer          default("x_api"), not null
#  platform(平台或通讯渠道)                                                                                               :integer          not null
#  priority(触达优先级（越小越优先）)                                                                                     :integer          default(0), not null
#  status(联系方式状态：active/invalid)                                                                                   :integer          default("active"), not null
#  url(主页链接或联系方式)                                                                                                :string(255)
#  created_at                                                                                                             :datetime         not null
#  updated_at                                                                                                             :datetime         not null
#  kol_id                                                                                                                 :bigint           not null
#  x_user_id(X平台 user id 缓存（@username 解析后缓存）)                                                                  :string(255)
#
# Indexes
#
#  index_kol_contacts_on_kol_id         (kol_id)
#  index_kol_contacts_on_monitor_until  (monitor_until)
#  index_kol_contacts_on_next_poll_at   (next_poll_at)
#  index_kol_contacts_on_platform       (platform)
#  index_kol_contacts_on_priority       (priority)
#  index_kol_contacts_on_status         (status)
#  index_kol_contacts_on_x_user_id      (x_user_id)
#
# Foreign Keys
#
#  fk_rails_...  (kol_id => kols.id)
#
class KolContact < ApplicationRecord
  belongs_to :kol
  has_many :kol_messages, dependent: :nullify

  # 平台/渠道枚举（社交平台 1-5 与内部 Account.platform 数值保持一致，便于映射）
  enum platform: {
    facebook: 1,
    twitter: 2,
    tiktok: 3,
    youtube: 4,
    instagram: 5,
    email: 6,
    telegram: 7,
    whatsapp: 8,
    linkedin: 9
  }

  enum status: {
    active: 0,       # 可用（尚未联系）
    disabled: 1,     # 停用（人工关闭）
    contacting: 2,   # 已联系，等回复（30 天窗口内）
    replied: 3,      # 已回复
    unresponsive: 4  # 未回复（30 天窗口到期仍无回复）
  }

  # 触达方式：指纹浏览器（机器端模拟）或 X 认证（X API 私信）
  enum outreach_channel: {
    browser: 0,  # 指纹浏览器（默认，兼容现有机器端链路）
    x_api: 1     # X 认证（X API 发私信/拉消息）
  }

  # 对方不可私信原因（人工在 X 页面验证后标记，用于后台区分「无法联系」的具体原因）
  enum dm_blocked_reason: {
    followers_only: 0,         # 仅关注者可私信
    requires_verification: 1,  # 需要验证账号
    dm_disabled: 2,            # 关闭私信
    account_suspended: 3,      # 账号被暂停
    username_not_found: 4      # @username 失效
  }

  # 对方不可私信原因中文标签
  DM_BLOCKED_REASON_LABELS = {
    "followers_only"         => "仅关注者可私信",
    "requires_verification"  => "需要验证账号",
    "dm_disabled"            => "关闭私信",
    "account_suspended"      => "账号被暂停",
    "username_not_found"     => "@username 失效"
  }.freeze

  def dm_blocked_reason_label
    DM_BLOCKED_REASON_LABELS[dm_blocked_reason] || nil
  end

  # 联系方式状态中文标签（展示用）
  STATUS_LABELS = {
    "active"       => "未联系",
    "disabled"     => "已停用",
    "contacting"   => "已联系·等回复",
    "replied"      => "已回复",
    "unresponsive" => "未回复"
  }.freeze

  def status_label
    STATUS_LABELS[status] || status.to_s
  end

  validates :platform, presence: true
  validates :url, presence: true

  # 该联系方式最后一次「发送成功」所用的内部账号（用于 check_reply / 人工回复）
  def last_outgoing_account
    kol_messages
      .where(direction: KolMessage.directions[:outgoing], status: KolMessage.statuses[:sent_success])
      .where.not(account_id: nil)
      .order(id: :desc)
      .first&.account
  end

  # 是否仍在回复监测窗口内
  def monitoring?
    contacting? && monitor_until.present? && monitor_until > Time.current
  end

  # 是否为内部社交账号平台（可调用内部账号发送私信）
  def social_platform?
    %w[facebook twitter tiktok youtube instagram].include?(platform)
  end

  # 是否真正走 X API 通道：只有 twitter 平台 + 显式「X认证」才走 X API。
  # 其它平台（instagram/tiktok/facebook 等）无 X DM 接口，一律走指纹浏览器（机器端）。
  def x_api_channel?
    platform.to_s == 'twitter' && outreach_channel == 'x_api'
  end

  # 触达/查回复接口的 target_url 参数：
  #   twitter：url 存 @username
  #   tiktok / instagram / facebook / youtube：url 存完整主页链接
  #   统一直接返回 url（url 为必填，不会为空）
  def outreach_target_url
    url.to_s.strip
  end

  # 平台展示图标（多平台名片夹 / 对话流气泡旁使用）
  def platform_icon
    {
      "facebook" => "📘",
      "twitter" => "🐦",
      "tiktok" => "🎵",
      "youtube" => "▶️",
      "instagram" => "📷",
      "email" => "📧",
      "telegram" => "✈️",
      "whatsapp" => "💬",
      "linkedin" => "💼"
    }[platform.to_s] || "🔗"
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[
      id kol_id platform nickname url priority messaging_enabled
      status outreach_channel x_user_id last_used_at last_sent_at next_poll_at
      dm_blocked_reason created_at updated_at
    ]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[kol]
  end
end
