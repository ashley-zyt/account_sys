module Api
	module V1
		# 视频资源接收接口
		# 职责：
		#   1. 接收外部采集脚本推送的视频链接及来源账号
		#   2. 主题匹配（基于本地配置文件）
		#   3. 为目标平台生成任务，并尝试立即分配可用账号
		#   4. 返回任务创建及分配结果
		class VideoReceiveController < ApplicationController
			# API 接口无需 CSRF 校验
			skip_before_action :verify_authenticity_token, only: [:create]

			# POST /api/v1/video/receive
			def create
				source_url = params[:source_url].to_s.strip
				video_url  = params[:video_url].to_s.strip

				# ---------- 1. 参数基础校验 ----------
				if source_url.blank? || video_url.blank?
					return render_bad_request('source_url 和 video_url 不能为空')
				end

				# ---------- 2. 主题匹配 ----------
				theme = ThemeConfig.match_theme(source_url)
				if theme.blank?
					return render_bad_request('来源账号未配置主题，拒绝入库')
				end

				# ---------- 3. 确定该主题下需要分发的平台列表 ----------
				# 策略：只为主题下至少有一个可用账号的平台创建任务
				#      避免产生永远无法分配的任务
				# platforms = target_platforms_for_theme(theme)
				# if platforms.empty?
				# 	return render_bad_request("主题「#{theme}」下无任何可用账号，无法创建任务")
				# end
				platforms = ["youtube", "facebook", "twitter", "tiktok"]
				# ---------- 4. 生成任务组ID，用于关联同一视频的多平台任务 ----------
				group_id = SecureRandom.uuid
				results = []

				# ---------- 5. 遍历平台，创建任务并尝试分配 ----------
				platforms.each do |platform|
					# 5.1 幂等性检查：同一视频在同一平台只能有一个任务
					existing_task = MoveTask.find_by(video_url: video_url, platform: MoveTask.platforms[platform])
					if existing_task
						# 已存在任务，直接返回现有信息（不重复创建）
						results << build_existing_task_result(existing_task, platform)
						next
					end

					# 5.2 生成标题（从主题标题池随机选取）
					title = ThemeConfig.random_title(theme)

					# 5.3 创建任务（任务分配失败初始状态 pending）
					task = MoveTask.create(video_url: video_url,source_account_url: source_url,theme: theme,platform: platform,title: title,status: :pending,group_id: group_id)
				end

				# ---------- 6. 返回最终处理结果 ----------
				render json: {code: 200,msg: '处理完成',group_id: group_id}
			end

			private

			# 获取指定主题下「需要分发」的平台列表
			# 实现方式：查询该主题下状态正常的账号，提取其平台并去重
			# 返回值示例：[:tiktok, :kuaishou, :youtube]
			def target_platforms_for_theme(theme)
				Account.active.where(theme: theme).distinct.pluck(:platform)
			end

			# 构建新创建任务的返回信息
			def build_task_result(task, allocated)
				{
					platform: task.platform,
					task_id: task.id,
					task_uuid: task.task_uuid,
					success: true,
					allocated: allocated,
					account_id: task.account_id,   # 分配成功时有值，否则 nil
					status: task.status
				}
			end

			# 构建已存在任务的返回信息（幂等情况）
			def build_existing_task_result(task, platform)
				{
					platform: platform,
					task_id: task.id,
					task_uuid: task.task_uuid,
					success: true,
					allocated: !task.pending?,     # 非 pending 即表示已分配过
					account_id: task.account_id,
					status: task.status,
					exists: true                  # 标记为已存在任务
				}
			end

			# 统一错误返回格式
			def render_bad_request(message)
				render json: { code: 400, msg: message }, status: :bad_request
			end
		end
	end
end