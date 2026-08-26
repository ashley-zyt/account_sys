# == Schema Information
#
# Table name: notebooklm_tasks
#
#  id                     :bigint           not null, primary key
#  actual_publish_time    :datetime
#  error_msg              :text(65535)
#  full_oss_url           :text(65535)
#  group_id               :string(255)
#  notebooklm_keyword_id  :bigint
#  keyword                :string(255)
#  oss_url                :text(65535)
#  platform               :integer
#  start_at               :datetime
#  status                 :integer          default("pending")
#  task_uuid              :string(255)
#  theme                  :string(255)
#  title                  :string(280)
#  description            :string(280)
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  account_id             :bigint
#  browser_id             :bigint
#
# Indexes
#
#  index_notebooklm_tasks_on_account_id             (account_id)
#  index_notebooklm_tasks_on_browser_id             (browser_id)
#  index_notebooklm_tasks_on_group_id               (group_id)
#  index_notebooklm_tasks_on_notebooklm_keyword_id  (notebooklm_keyword_id)
#  index_notebooklm_tasks_on_platform               (platform)
#  index_notebooklm_tasks_on_status                 (status)
#  index_notebooklm_tasks_on_task_uuid              (task_uuid) UNIQUE
#  index_notebooklm_tasks_on_theme                  (theme)
#
class NotebooklmTask < ApplicationRecord
  belongs_to :browser, optional: true
  belongs_to :account, optional: true
  belongs_to :notebooklm_keyword, optional: true

  enum status: {
    pending: 0,          # 待分配账号
    waiting_publish: 1,  # 等待发布
    executing: 2,        # 执行中
    success: 3,          # 成功
    failed: 4            # 失败
  }

  # 平台枚举（与 HuashengTask 保持一致）
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

  # OSS 凭证与 notebooklm_keywords 共用同一个 bucket（notebooklm-ld）。
  OSS_BUCKET = "notebooklm-ld".freeze
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
    %w[id task_uuid oss_url full_oss_url theme title description keyword status error_msg start_at actual_publish_time account_id browser_id platform group_id notebooklm_keyword_id created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[account browser notebooklm_keyword]
  end

  # OSS V1 GET 签名 URL
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

  # 将已完成的 NotebooklmKeyword 推送到 NotebookLM 资源队列：每条关键词生成 5 条任务（每平台一条）。
  #
  # 字段映射规则（result_data.Script 含 title/caption）：
  #   - youtube：notebooklm_task.title   = Script.title  （截断 100 字符）
  #             notebooklm_task.description = Script.caption（截断 280 字符）
  #   - 其他平台：notebooklm_task.title      = Script.caption（截断 280 字符）
  #              notebooklm_task.description = ""（空）
  #
  # 入参 notebooklm_keyword 必须是 status=3（执行完成）且 result_data 中含有
  # oss_url（object key）和 Script。
  # 幂等：同一 notebooklm_keyword 重复调用不会重复创建（按 notebooklm_keyword_id 去重）。
  # 返回 [created_count, error_message]
  def self.create_from_notebooklm_keyword!(notebooklm_keyword)
    return [0, "notebooklm_keyword 不能为空"] if notebooklm_keyword.nil?
    return [0, "NotebookLM关键词未完成，无法入库"] unless notebooklm_keyword.status == 3

    # 已存在则跳过（幂等）
    if where(notebooklm_keyword_id: notebooklm_keyword.id).exists?
      return [0, "该关键词已入库资源队列"]
    end

    result = (JSON.parse(notebooklm_keyword.result_data) rescue {})
    object_key = result["oss_url"].to_s.strip.gsub(/^`|`$/, "").strip
    return [0, "result_data 中缺少 oss_url"] if object_key.blank?

    # Script 结构：{ topic, script, title, caption, tags }
    script = result["Script"].is_a?(Hash) ? result["Script"] : (result["script"].is_a?(Hash) ? result["script"] : {})
    title_text = script["title"].to_s.strip
    caption    = script["caption"].to_s.strip

    theme    = notebooklm_keyword.theme.to_s
    keyword  = notebooklm_keyword.keyword.to_s

    signed_url = oss_v1_sign_url(object_key)
    group_id   = SecureRandom.uuid

    created = 0
    ALL_PLATFORMS.each do |platform_name|
      if platform_name == "youtube"
        # youtube: title = Script.title（限 100），description = Script.caption（限 280）
        task_title = title_text[0...100]
        task_desc  = caption[0...280]
      else
        # 其他平台: title = Script.caption（限 280），description 为空
        task_title = caption[0...280]
        task_desc  = ""
      end

      task = new(
        notebooklm_keyword_id: notebooklm_keyword.id,
        keyword:     keyword,
        theme:       theme,
        full_oss_url: object_key,
        oss_url:     signed_url,
        platform:    platform_name,
        status:      :pending,
        group_id:    group_id,
        title:       task_title,
        description: task_desc
      )
      created += 1 if task.save
    end

    [created, nil]
  end

  private

  def generate_task_uuid
    self.task_uuid ||= "NL-#{SecureRandom.uuid}"
  end
end