# == Schema Information
#
# Table name: browsers
#
#  id                                                    :bigint           not null, primary key
#  profile_name(指纹浏览器名称)                          :string(255)
#  proxy_host(代理IP)                                    :string(255)
#  proxy_password(代理密码)                              :string(255)
#  proxy_port(代理端口)                                  :integer
#  proxy_type(代理类型 http/socks5)                      :string(255)
#  proxy_username(代理用户名)                            :string(255)
#  purpose(用途：养号/采集)                              :integer          default("warmup")
#  remark(备注信息)                                      :string(255)
#  status(浏览器状态：online/offline/network_error/busy) :integer          default("online")
#  created_at                                            :datetime         not null
#  updated_at                                            :datetime         not null
#  cloud_id(指纹浏览器名称ID)                            :string(255)
#
class Browser < ApplicationRecord
	# 一个浏览器可被多个账号绑定（如一个浏览器登录多个账号）
	has_many :accounts, dependent: :nullify

	# 一个浏览器可执行多个发布任务（任务执行时会记录快照 browser_id）
	has_many :move_tasks, dependent: :nullify

	# 浏览器状态枚举
	# - online        : 在线且空闲，可分配任务
	# - offline       : 离线（关机、未启动）
	# - network_error : 网络异常（代理失效、无法联网）
	# - busy          : 忙碌（正在执行任务，暂不接收新任务）
	enum status: {
		"正常": 0,          # 正常可用
		"网络问题": 1        # 网络问题
	}

	# 浏览器用途枚举
	# - warmup    : 养号（模拟正常行为，暂不用于发布）
	# - collection: 采集（用于视频采集任务，当前系统未使用）
	enum purpose: {
		"账号培育": 0,   # 养号
		"采集": 1   # 采集
	}

	
	# 作用域：获取当前可用的浏览器（仅 正常 状态）
	# 注意：此处未实现并发控制，单任务环境下直接使用即可
	scope :available, -> {
		正常
	}

	def self.ransackable_attributes(auth_object = nil)
		%w[
			id
			profile_name
			cloud_id
			proxy_type
			proxy_host
			proxy_port
			proxy_username
			proxy_password
			status
			purpose
			remark
			created_at
			updated_at
		]
	end
	# ✅ 允许 Ransack 搜索关联
	def self.ransackable_associations(auth_object = nil)
		["accounts", "move_tasks"]
	end

end
