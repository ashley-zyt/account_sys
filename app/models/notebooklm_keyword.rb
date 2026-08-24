# == Schema Information
#
# Table name: notebooklm_keywords
#
#  id                                                            :bigint           not null, primary key
#  keyword(关键词)                                               :string(255)      not null
#  pushed(是否已推送到NotebookLM资源队列)                        :boolean          default(FALSE), not null
#  result_data(采集结果数据（JSON）)                             :text(65535)
#  status(任务状态：0未启动 1待执行 2执行中 3执行完成 4任务失败) :integer          default(0)
#  theme(主题)                                                   :string(255)      not null
#  created_at                                                    :datetime         not null
#  updated_at                                                    :datetime         not null
#  task_id(远程任务ID)                                           :string(255)
#
# Indexes
#
#  index_notebooklm_keywords_on_pushed            (pushed)
#  index_notebooklm_keywords_on_status            (status)
#  index_notebooklm_keywords_on_theme             (theme)
#  index_notebooklm_keywords_on_theme_and_status  (theme,status)
#
class NotebooklmKeyword < ApplicationRecord
  STATUS_NAMES = {
    0 => "未启动",
    1 => "待执行",
    2 => "执行中",
    3 => "执行完成",
    4 => "任务失败"
  }.freeze

  validates :theme, :keyword, presence: true

  scope :by_theme, ->(theme) { where(theme: theme) if theme.present? }
  scope :by_status, ->(status) { where(status: status) if status.present? }

  def self.ransackable_attributes(auth_object = nil)
    %w[id theme keyword status task_id pushed created_at updated_at]
  end

  def status_name
    STATUS_NAMES[status] || "未知"
  end

  # OSS 签名 URL（bucket: notebooklm-ld）
  OSS_BUCKET = "notebooklm-ld".freeze
  OSS_REGION = "cn-hangzhou".freeze
  OSS_ACCESS_KEY_ID = "gZL8z938T19mSUHf".freeze
  OSS_ACCESS_KEY_SECRET = "A9fSDa9cH5YAExpEUR4QSizkFQEcrS".freeze
  OSS_SIGNED_URL_TTL = 31_536_000 # 1 年

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
end
