# == Schema Information
#
# Table name: jianying_tasks
#
#  id                                                                :bigint           not null, primary key
#  actual_publish_time(实际发布时间)                                 :datetime
#  error_msg(错误信息/失败原因)                                      :text(65535)
#  oss_url(剪映生成的视频OSS地址)                                   :text(65535)
#  platform(目标发布平台)                                            :integer
#  start_at(任务开始时间)                                            :datetime
#  status(任务状态 pending/waiting_publish/executing/success/failed) :integer          default("pending")
#  task_uuid(任务唯一标识，用于关联日志)                             :string(255)
#  theme(内容主题)                                                   :string(255)
#  title(发布标题)                                                   :text(65535)
#  keyword(关键词)                                                   :string(255)
#  keyword_code(关键词编码)                                          :string(255)
#  associated_images(关联图片JSON数组)                               :text(65535)
#  created_at                                                        :datetime         not null
#  updated_at                                                        :datetime         not null
#  account_id(发布账号ID)                                            :bigint
#  browser_id(执行任务的浏览器ID)                                    :bigint
#  group_id(任务组ID)                                                :string(255)
#
# Indexes
#
#  index_jianying_tasks_on_account_id  (account_id)
#  index_jianying_tasks_on_browser_id  (browser_id)
#  index_jianying_tasks_on_group_id    (group_id)
#  index_jianying_tasks_on_keyword_code (keyword_code)
#  index_jianying_tasks_on_platform    (platform)
#  index_jianying_tasks_on_status      (status)
#  index_jianying_tasks_on_task_uuid   (task_uuid) UNIQUE
#  index_jianying_tasks_on_theme       (theme)
#
class JianyingTask < ApplicationRecord
	belongs_to :browser, optional: true
	belongs_to :account, optional: true

	enum status: {
		pending: 0,          # 待分配账号
		waiting_publish: 1,  # 等待发布
		executing: 2,        # 执行中
		success: 3,          # 成功
		failed: 4            # 失败
	}

	# 平台枚举
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

	# 作用域：获取可执行任务
	scope :runnable, -> {
		where(status: :waiting_publish)
	}

	# 作用域：按主题筛选待分配任务
	scope :pending_for_theme, ->(theme) {
		where(status: :pending, theme: theme).order(created_at: :asc)
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

	# Ransack 搜索允许的字段
	def self.ransackable_attributes(auth_object = nil)
		%w[id task_uuid oss_url theme title keyword keyword_code status error_msg start_at actual_publish_time account_id browser_id platform group_id created_at updated_at]
	end

	def self.ransackable_associations(auth_object = nil)
		%w[account browser]
	end

	# 根据 API 接收的数据批量创建任务（每项数据生成 5 条，对应 5 个平台）
	# item = { keyword:, keyword_code:, theme:, associated_images:, oss_key: }
	def self.batch_create_from_api(items)
		created = 0
		items.each do |item|
			group_id = SecureRandom.uuid
			ALL_PLATFORMS.each do |platform|
				task = new(
					keyword: item[:keyword],
					keyword_code: item[:keyword_code],
					theme: item[:theme],
					associated_images: item[:associated_images].is_a?(Array) ? item[:associated_images].to_json : item[:associated_images],
					oss_url: item[:oss_key],
					platform: platform,
					status: :pending,
					group_id: group_id,
					title: generate_title(item[:theme], item[:keyword])
				)
				created += 1 if task.save
			end
		end
		created
	end

	# 根据主题和关键词生成标题
	# 1. 从 Theme 表中找到对应主题
	# 2. 从主题的 titles 中随机选一行作为标题模板
	# 3. 从主题的 prompts 中匹配当前关键词的行，提取括号里的英文字符串
	# 4. 用提取的英文字符串替换标题模板中的 ****
	def self.generate_title(theme_name, keyword_text)
		theme = Theme.find_by(name: theme_name)
		return default_title(theme_name) unless theme

		titles = theme.titles_array
		return default_title(theme_name) if titles.empty?

		template = titles.sample

		# 尝试替换 **** 为从 prompts 中提取的文本
		english = extract_english_from_prompts(theme, keyword_text)
		if english.present? && template.include?("****")
			template.gsub("****", english)
		elsif template.include?("****")
			template.gsub("****", keyword_text)
		else
			template
		end
	end

	# 从主题 prompts 中匹配关键词行，提取第一个括号内的英文字符串
	# prompts 格式示例：
	#   #北海#涠洲岛海景竖图素材 (seaside landscape vertical)
	#   #上海#外滩璀璨夜景竖图素材 (Bund night scenery)
	def self.extract_english_from_prompts(theme, keyword_text)
		return nil unless theme.prompts.present?

		theme.prompts_array.each do |line|
			next unless line.include?(keyword_text) || keyword_text.include?(line.split("(").first.to_s.strip)

			if line =~ /\(([^)]+)\)/
				return $1.strip
			end
		end
		nil
	end

	def self.default_title(theme_name)
		"#{theme_name} - Amazing Video"
	end

	# 已废弃：从 OSS 加载视频资源
	def self.load_oss_source_task
		endpoint = 'https://oss-cn-hangzhou.aliyuncs.com'
		access_key_id = ENV['ALIYUN_ACCESS_KEY_ID']
		access_key_secret = ENV['ALIYUN_ACCESS_KEY_SECRET']
		bucket_name = 'jianying-videos'
		client = Aliyun::OSS::Client.new(
			endpoint: endpoint,access_key_id: access_key_id,access_key_secret: access_key_secret
		)
		bucket = client.get_bucket(bucket_name)
		prefix_data = {"wulongwushi"=>"舞狮舞龙","food"=>"中国美食制作","hanfu"=>"汉服秀","mimgshengguji"=>"名胜古迹","zhongguowu"=>"中国舞","wushu"=>"武术表演"}
		# prefix_data = {"wulongwushi"=>"舞狮舞龙"}
		prefix_data.each do |prefix_d|
			p prefix = prefix_d[0]
			p theme = prefix_data[prefix]
			objects = bucket.list_objects(prefix: prefix)
			objects.each do |obj|
				obj_key = obj.key
				if obj_key != prefix+"/"
					expire_at = Time.parse('2027-12-31 23:59:59')
					p video_url = bucket.object_url(obj_key, expire_at)
					platforms = ["youtube", "facebook", "twitter", "tiktok"]
					group_id = SecureRandom.uuid
					results = []
					platforms.each do |platform|
						filename = video_url.split("hangzhou.aliyuncs.com/").last.split("?Expires=").first
						existing_task = JianyingTask.where(platform: platform).where("oss_url like '%#{filename}%'").count
						if existing_task > 0
							# 已存在任务，直接返回现有信息（不重复创建）
							next
						end
						title = ThemeConfig.random_title(theme)
						task = JianyingTask.create(oss_url: video_url,theme: theme,title: title,status: "pending",platform: platform,group_id: group_id)

					end
				end
			end
		end
	end

	private

	def generate_task_uuid
		self.task_uuid ||= "JY-#{SecureRandom.uuid}"
	end
end
