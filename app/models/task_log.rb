# == Schema Information
#
# Table name: task_logs
#
#  id                                                   :bigint           not null, primary key
#  error_msg(执行错误信息)                              :text(65535)
#  request_data(请求参数/发送内容)                      :text(65535)
#  response_data(接口返回数据)                          :text(65535)
#  run_at(执行时间)                                     :datetime
#  status(执行结果 success/failed)                      :integer          default("success")
#  task_uuid(关联的任务UUID)                            :string(255)
#  created_at                                           :datetime         not null
#  updated_at                                           :datetime         not null
#  account_id(执行账号ID快照（任务释放后仍保留关联）)   :bigint
#  browser_id(执行浏览器ID快照（任务释放后仍保留关联）) :string(255)
#
# Indexes
#
#  index_task_logs_on_account_id  (account_id)
#  index_task_logs_on_browser_id  (browser_id)
#  index_task_logs_on_run_at      (run_at)
#  index_task_logs_on_status      (status)
#  index_task_logs_on_task_uuid   (task_uuid)
#
class TaskLog < ApplicationRecord
	# 与各资源队列任务的反查关联，由 WorkMode 注册表动态生成
	# （新增工作模式无需改动本文件）
	WorkMode.resource_modes.each do |mode|
		belongs_to mode.singular_association_name, foreign_key: :task_uuid, primary_key: :task_uuid, optional: true
	end

	# 任务释放后仍然能定位到执行账号/浏览器
	belongs_to :log_account, class_name: 'Account', foreign_key: :account_id, optional: true
	belongs_to :log_browser, class_name: 'Browser', foreign_key: :browser_id, optional: true

	# 获取当前关联的具体任务对象（按注册表遍历各资源队列）
	def task
		WorkMode.resource_modes.map { |m| public_send(m.singular_association_name) }.compact.first
	end

	# 获取任务类型标签（由注册表的 log_label 提供）
	def task_type
		mode = WorkMode.resource_modes.find { |m| public_send(m.singular_association_name).present? }
		mode ? mode.log_label : "未知"
	end

	# 基础校验
	validates :task_uuid, presence: true

	# 日志状态
	enum status: {
		success: 0,
		failed: 1
	}

	# 作用域：获取今日产生的日志
	scope :today, -> {
		where("created_at >= ?", Time.zone.now.beginning_of_day)
	}

	# 获取展示用的账号对象（优先使用快照，避免运营任务释放后关联丢失）
	def display_account
		return log_account if account_id.present?

		if task_uuid == "999"
			begin
				data = eval(response_data)
				Account.find_by(id: data["id"]) if data["id"].present?
			rescue JSON::ParserError, SyntaxError, NameError
				nil
			end
		else
			task&.account
		end
	end

	# 获取展示用的平台名称
	def display_platform
		display_account&.platform || "未知"
	end

	# 获取展示用的浏览器对象（优先使用快照）
	def display_browser
		return log_browser if browser_id.present?

		if task_uuid == "999"
			display_account&.browser
		else
			task&.browser
		end
	end

	# 生成「快照优先 + 各资源队列任务回退」的 COALESCE 子查询片段
	# 注意：必须在 ransacker 之前定义，因为 ransacker 的 block 在类加载时立即求值
	# @param column [String] 要取值的字段（platform / work_type）
	def self.account_snapshot_fallback_sql(column)
		snapshot = "(SELECT a.#{column} FROM accounts a WHERE a.id = task_logs.account_id LIMIT 1)"
		fallbacks = WorkMode.resource_modes.map { |m|
			"(SELECT a.#{column} FROM #{m.association_name} _t JOIN accounts a ON a.id = _t.account_id WHERE _t.task_uuid = task_logs.task_uuid LIMIT 1)"
		}
		([snapshot] + fallbacks).join(", ")
	end

	# 任务类型筛选：按注册表动态生成「该 task_uuid 属于哪张资源表」的 CASE 表达式
	ransacker :task_type do
		cases = WorkMode.resource_modes.map { |m|
			"WHEN EXISTS (SELECT 1 FROM #{m.association_name} WHERE #{m.association_name}.task_uuid = task_logs.task_uuid) THEN '#{m.key}_task'"
		}.join(" ")
		Arel.sql("CASE #{cases} ELSE 'unknown' END")
	end

	# 账号所属平台：优先读取快照字段，回退到各资源队列任务再到 accounts 表
	ransacker :account_platform, formatter: proc { |v| Account.platforms[v] } do
		Arel.sql("COALESCE(#{account_snapshot_fallback_sql('platform')})")
	end

	# 工作模式筛选：优先读取快照字段，回退到各资源队列任务再到 accounts 表
	ransacker :account_work_type, formatter: proc { |v| Account.work_types[v] } do
		Arel.sql("COALESCE(#{account_snapshot_fallback_sql('work_type')})")
	end

	def self.ransackable_associations(auth_object = nil)
		WorkMode.resource_modes.map { |m| m.singular_association_name.to_s } + %w[log_account log_browser]
	end

	def self.ransackable_attributes(auth_object = nil)
		%w[
			id
			task_uuid
			request_data
			response_data
			status
			error_msg
			run_at
			account_id
			browser_id
			created_at
			updated_at
			task_type
			account_platform
			account_work_type
		]
	end
end
