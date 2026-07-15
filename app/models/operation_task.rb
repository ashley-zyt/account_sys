# == Schema Information
#
# Table name: operation_tasks
#
#  id                                :bigint           not null, primary key
#  actual_publish_time(实际发布时间) :datetime
#  description                       :text(65535)
#  error_msg(错误信息)               :text(65535)
#  oss_url(OSS文件地址)              :string(255)
#  platform                          :integer
#  start_at(开始时间)                :datetime
#  status                            :integer          default("pending")
#  task_uuid(任务UUID)               :string(255)
#  theme(主题)                       :string(255)
#  title(标题)                       :string(255)
#  created_at                        :datetime         not null
#  updated_at                        :datetime         not null
#  account_id(账号ID)                :bigint
#  browser_id(浏览器ID)              :string(255)
#  group_id(分组ID)                  :bigint
#
# Indexes
#
#  index_operation_tasks_on_account_id              (account_id)
#  index_operation_tasks_on_account_id_and_oss_url  (account_id,oss_url) UNIQUE
#  index_operation_tasks_on_oss_url_and_platform    (oss_url,platform) UNIQUE
#  index_operation_tasks_on_status                  (status)
#  index_operation_tasks_on_task_uuid               (task_uuid) UNIQUE
#

class OperationTask < ApplicationRecord
	belongs_to :account, optional: true
	belongs_to :browser, optional: true

	enum status: {
		pending: 0,          # 待分配账号
		waiting_publish: 1,  # 等待发布
		executing: 2,        # 执行中
		success: 3,          # 成功
		failed: 4            # 失败
	}

	enum platform: {
		facebook: 1,
		twitter: 2,
		tiktok: 3,
		youtube: 4,
		instagram: 5
	}

	validates :title, presence: true
	validates :oss_url, presence: true
	validates :task_uuid, uniqueness: true, allow_nil: true
	validates :platform, presence: true

	# 非 pending 状态必须有账号
	validates :account_id, presence: true, unless: :pending?

	before_validation :normalize_newlines, on: [:create, :update]
	before_validation :generate_task_uuid, on: :create

	# 作用域：获取可执行任务
	scope :runnable, -> {
		where(status: :waiting_publish)
	}

	# 作用域：按平台筛选待分配任务
	scope :pending_for_platform, ->(platform) {
		where(status: :pending, platform: platform).order(created_at: :asc)
	}

	# 最近任务
	scope :recent, -> {
		order(created_at: :desc)
	}

	# 重置任务到 pending 状态
	def reset_to_pending!
		update!(
			account_id: nil,
			browser_id: nil,
			status: :pending,
			start_at: nil
		)
	end

	def self.ransackable_attributes(auth_object = nil)
		%w[id task_uuid oss_url theme title description status error_msg start_at actual_publish_time account_id browser_id platform group_id created_at updated_at]
	end

	def self.ransackable_associations(auth_object = nil)
		["account"]
	end

	# 重新生成 OSS 签名 URL（有效期1年）
	def regenerate_oss_url!
		# 从现有的 oss_url 中提取文件名（key）
		return false if oss_url.blank?
		
		# 解析 URL，提取 bucket 和文件名
		uri = URI.parse(oss_url)
		path = uri.path
		
		# 移除开头的 '/'
		key = path.sub(/^\//, '')
		
		# 如果有查询参数，只保留路径部分
		key = key.split('?').first if key.include?('?')
		
		# 生成新的签名 URL
		new_url = OperationTask.generate_signed_url(key)
		
		# 更新记录
		update!(oss_url: new_url)
		true
	end

	# 批量重新生成所有任务的 OSS URL
	def self.regenerate_all_oss_urls!
		count = 0
		OperationTask.all.each do |task|
			if task.regenerate_oss_url!
				count += 1
			end
		end
		count
	end

	# 生成 OSS 签名 URL（有效期1年）
	def self.generate_signed_url(key)
		require 'base64'
		require 'openssl'
		
		access_key_id = ENV['ALIYUN_ACCESS_KEY_ID']
		access_key_secret = ENV['ALIYUN_ACCESS_KEY_SECRET']
		bucket_name = 'operation-viodes'
		
		return nil if access_key_id.blank? || access_key_secret.blank?
		
		verb = "GET"
		content_md5 = ""
		content_type = ""
		ts = (Time.now.to_i + 31536000)  # 1年有效期
		
		# 签名字符串中的 key 使用原始路径（不编码）
		cano_res = "/#{bucket_name}/#{key}"
		sign_string = "#{verb}\n#{content_md5}\n#{content_type}\n#{ts}\n#{cano_res}"
		
		# 生成签名
		signature = OpenSSL::HMAC.digest("sha1", access_key_secret, sign_string).to_s
		signature = Base64.strict_encode64(signature).strip
		signature = URI.encode_www_form_component(signature)
		
		# URL 中的 key 需要编码
		encoded_key = URI.encode_www_form_component(key)
		
		# 构建最终的签名 URL
		"https://#{bucket_name}.oss-cn-hangzhou.aliyuncs.com/#{encoded_key}?OSSAccessKeyId=#{access_key_id}&Expires=#{ts}&Signature=#{signature}"
	end

	private

	def generate_task_uuid
		self.task_uuid ||= "OP-#{SecureRandom.uuid}"
	end

	def normalize_newlines
		self.title = normalize_text(title) if title.present?
		self.description = normalize_text(description) if description.present?
	end

	def normalize_text(text)
		text
			.gsub("\r\n", "\n")
			.gsub("\r", "\n")
			.gsub(/\n+/, "\n")
	end
end
