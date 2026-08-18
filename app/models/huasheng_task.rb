# == Schema Information
#
# Table name: huasheng_tasks
#
#  id                   :bigint           not null, primary key
#  actual_publish_time  :datetime
#  error_msg            :text(65535)
#  full_oss_url         :text(65535)
#  group_id             :string(255)
#  huasheng_keyword_id  :bigint
#  keyword              :string(255)
#  oss_url              :text(65535)
#  platform             :integer
#  start_at             :datetime
#  status               :integer          default("pending")
#  task_uuid            :string(255)
#  theme                :string(255)
#  title                :string(280)
#  description          :string(280)
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  account_id           :bigint
#  browser_id           :bigint
#
# Indexes
#
#  index_huasheng_tasks_on_account_id           (account_id)
#  index_huasheng_tasks_on_browser_id           (browser_id)
#  index_huasheng_tasks_on_group_id             (group_id)
#  index_huasheng_tasks_on_huasheng_keyword_id  (huasheng_keyword_id)
#  index_huasheng_tasks_on_platform             (platform)
#  index_huasheng_tasks_on_status               (status)
#  index_huasheng_tasks_on_task_uuid            (task_uuid) UNIQUE
#  index_huasheng_tasks_on_theme                (theme)
#
class HuashengTask < ApplicationRecord
  belongs_to :browser, optional: true
  belongs_to :account, optional: true
  belongs_to :huasheng_keyword, optional: true

  enum status: {
    pending: 0,          # 待分配账号
    waiting_publish: 1,  # 等待发布
    executing: 2,        # 执行中
    success: 3,          # 成功
    failed: 4            # 失败
  }

  # 平台枚举（与 JianyingTask 保持一致）
  enum platform: {
    facebook: 1,
    twitter: 2,
    tiktok: 3,
    youtube: 4,
    instagram: 5
  }

  ALL_PLATFORMS = %w[facebook twitter tiktok youtube instagram].freeze

  validates :task_uuid, presence: true, uniqueness: true
  validates :oss_url, presence: true
  validates :platform, presence: true
  validates :theme, presence: true

  # 非 pending 状态必须有账号
  validates :account_id, presence: true, unless: :pending?

  before_validation :generate_task_uuid, on: :create

  scope :runnable, -> { where(status: :waiting_publish) }
  scope :recent, -> { order(created_at: :desc) }

  # OSS 凭证与 huasheng_keywords 共用同一个 bucket（huasheng-ld）。
  OSS_BUCKET = "huasheng-ld".freeze
  OSS_REGION = "cn-hangzhou".freeze
  OSS_ACCESS_KEY_ID = "gZL8z938T19mSUHf".freeze
  OSS_ACCESS_KEY_SECRET = "A9fSDa9cH5YAExpEUR4QSizkFQEcrS".freeze
  OSS_SIGNED_URL_TTL = 31_536_000 # 1 年

  # 重置任务到 pending 状态
  def reset_to_pending!
    update!(
      account_id: nil,
      browser_id: nil,
      status: :pending,
      start_at: nil
    )
  end

  # Ransack 搜索允许的字段
  def self.ransackable_attributes(auth_object = nil)
    %w[id task_uuid oss_url full_oss_url theme title description keyword status error_msg start_at actual_publish_time account_id browser_id platform group_id huasheng_keyword_id created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[account browser huasheng_keyword]
  end

  # OSS V1 GET 签名 URL（参考 huasheng_keywords_controller#huasheng_oss_v1_sign_url）
  def self.percent_encode(str)
    URI.encode_www_form_component(str.to_s).gsub("+", "%20")
  end

  def self.oss_v1_sign_url(key, expires_seconds = OSS_SIGNED_URL_TTL)
    return nil if key.blank?
    require "openssl"
    require "base64"

    key = key.sub(%r{^/}, "")
    expires = (Time.now.utc.to_i + expires_seconds).to_s
    string_to_sign = "GET\n\n\n#{expires}\n/#{OSS_BUCKET}/#{key}"
    signature = Base64.strict_encode64(
      OpenSSL::HMAC.digest("sha1", OSS_ACCESS_KEY_SECRET, string_to_sign)
    ).strip

    encoded_key = key.split("/").map { |seg| percent_encode(seg) }.join("/")
    "https://#{OSS_BUCKET}.oss-#{OSS_REGION}.aliyuncs.com/#{encoded_key}?" \
      "OSSAccessKeyId=#{OSS_ACCESS_KEY_ID}" \
      "&Expires=#{expires}" \
      "&Signature=#{percent_encode(signature)}"
  end

  private

  def generate_task_uuid
    self.task_uuid ||= "HS-#{SecureRandom.uuid}"
  end
end
