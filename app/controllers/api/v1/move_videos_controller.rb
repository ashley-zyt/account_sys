module Api
	module V1
		# 搬运视频资源接口（下载转存 + 剪映处理）
		#
		# 流程：
		#   import            录入源视频 → move_video(pending_download)
		#   fetch_for_download   下载软件拉取 → downloading
		#   report_download      下载完成回传 path → 校验 OSS 存在并生成签名 URL 存 raw_oss_url → pending_process
		#   fetch_for_processing 剪映项目拉取 → processing
		#   report_processing    剪映完成回传 processed_oss_url → processed + 创建多平台 move_task
		class MoveVideosController < ApplicationController
			skip_before_action :verify_authenticity_token
			rescue_from MoveVideo::StateError, with: :render_state_error

			include OssSignedUrl

			DEFAULT_PLATFORMS_STR = MoveVideo::DEFAULT_PLATFORMS.join(',')
			# 下载转存目标 bucket（下载软件上传到此 bucket，本系统校验存在并生成签名 URL）
			OSS_BUCKET = 'jianying-videos'

			# 下载软件所在机器的标准视频目录
			# 下载软件回传的 path 有时会丢失路径分隔符 /，如
			#   "C:UsersAdministratorDesktopvideosxxx.mp4" 实际应为 "C:/Users/Administrator/Desktop/videos/xxx.mp4"
			# 据此常量还原标准路径前缀，确保后续能正确解析出文件名
			DOWNLOAD_STANDARD_DIR = 'C:/Users/Administrator/Desktop/videos/'.freeze

			# ---------- 1. 录入源视频 ----------
			# POST /api/v1/move_videos/import
			# 入参：source_url(来源账号主页链接)、video_url(源视频链接)、platforms(可选，逗号分隔)
			# 主题由 ThemeConfig 按 source_url 匹配；幂等：同一 video_url 重复录入返回已存在记录
			def import
				source_url = params[:source_url].to_s.strip
				video_url  = params[:video_url].to_s.strip
				platforms  = params[:platforms].to_s.strip
				source_title = params[:source_title].to_s.strip

				if source_url.blank? || video_url.blank?
					return render_error('source_url 和 video_url 不能为空')
				end

				theme = ThemeConfig.match_theme(source_url)
				return render_error('来源账号未配置主题，拒绝入库') if theme.blank?

				platforms_str = platforms.present? ? platforms : DEFAULT_PLATFORMS_STR

				existed = MoveVideo.exists?(source_video_url: video_url)
				begin
					move_video = MoveVideo.create_from_import!(
						source_video_url: video_url,
						source_account_url: source_url,
						theme: theme,
						platforms: platforms_str,
						source_title: source_title.presence
					)
				rescue ActiveRecord::RecordNotUnique
					# 并发下同 video_url 重复创建，直接取已存在记录
					move_video = MoveVideo.find_by!(source_video_url: video_url)
					existed = true
				end

				render_success(data: {
					id: move_video.id,
					video_url: move_video.source_video_url,
					source_title: move_video.source_title,
					source_account_url: move_video.source_account_url,
					theme: move_video.theme,
					group_id: move_video.group_id,
					platforms: move_video.platforms,
					status: move_video.status,
					exists: existed
				})
			end

			# ---------- 2. 下载软件拉取待下载视频 ----------
			# GET /api/v1/move_videos/fetch_for_download
			# 原子 claim 一条 pending_download → downloading，无任务返回 data:{id:null}
			def fetch_for_download
				move_video = MoveVideo.claim_for_download!
				return render_success(data: { id: nil }) if move_video.nil?

				render_success(data: build_download_payload(move_video))
			end

			# ---------- 3. 下载完成回调（融合原 video_url 的 OSS 签名逻辑）----------
			# POST /api/v1/move_videos/report_download
			# 入参：id、path(下载后上传到 OSS 的文件路径/URL)
			# 无需 status：调用即视为下载软件已尝试上传。系统校验文件在 jianying-videos bucket 中是否存在：
			#   存在   → 生成签名 URL 存 raw_oss_url → 标记下载成功（pending_process）
			#   不存在 → 标记下载失败（failed）
			# 文件名解析失败 / OSS 凭证未配置等属于请求或配置异常，不改动 move_video 状态，直接返回 error
			def report_download
				move_video = find_move_video
				return unless move_video

				path = params[:path].to_s.strip
				return render_error('path 不能为空') if path.blank?

				# 下载软件回传的 path 有时丢失了 /，按标准目录前缀还原后再做 OSS 校验
				path = normalize_download_path(path) unless path.include?('/')

				result = resolve_oss_signed_url(path, OSS_BUCKET)
				if result[:ok]
					move_video.mark_downloaded!(result[:signed_url])
					render_success(
						message: '下载完成已记录',
						data: { raw_oss_url: result[:signed_url], bucket: result[:bucket], filename: result[:filename] }
					)
				elsif result[:reason] == :not_found
					# bucket 中不存在文件 → 视频下载失败
					move_video.mark_download_failed!("下载失败：OSS 中未找到该文件")
					render_success(message: '下载失败已记录（OSS 中未找到文件）', data: { error: result[:error] })
				else
					# invalid_filename / no_credentials 等异常 → 不改动状态，直接返回错误
					render_error(result[:error])
				end
			end

			# ---------- 4. 剪映项目拉取待处理视频 ----------
			# GET /api/v1/move_videos/fetch_for_processing
			# 原子 claim 一条 pending_process → processing，返回 raw_oss_url 供剪映下载
			def fetch_for_processing
				move_video = MoveVideo.claim_for_processing!
				return render_success(data: { id: nil }) if move_video.nil?

				render_success(data: {
					id: move_video.id,
					raw_oss_url: move_video.raw_oss_url,
					theme: move_video.theme,
					group_id: move_video.group_id
				})
			end

			# ---------- 4.1 批量领取待混剪视频（mashup 混剪程序）----------
			# GET /api/v1/move_videos/fetch_pending_process_batch
			# 入参：theme（可选，主题名）
			#   指定 theme：该主题最多取 100 条（不足 100 全取）
			#   不指定 theme：遍历所有主题，每个主题各取 50 条（不足 50 全取该主题）
			# 原子 claim：每条「待混剪」→「混剪中」，并发安全，被抢的自动跳过
			def fetch_pending_process_batch
				theme = params[:theme].to_s.strip

				candidates = if theme.present?
					MoveVideo.pending_hunjian.where(theme: theme).order(created_at: :asc).limit(100).to_a
				else
					pending_hunjian_candidates_across_themes(50)
				end

				claimed = []
				candidates.each do |record|
					claimed << record if record.claim_hunjian!
				end

				render_success(data: {
					count: claimed.size,
					items: claimed.map { |v| build_pending_process_item(v) }
				})
			end

			# ---------- 5. 剪映完成回调 ----------
		# POST /api/v1/move_videos/report_processing
		# 入参：id、status('success'|'error')、processed_oss_url、error_msg
		# success：→ processed，成片 URL 写入每条 move_task.oss_url，并创建多平台 move_task（pending）
		def report_processing
			move_video = find_move_video
			return unless move_video

			status = params[:status].to_s.strip
			if status == 'success'
				processed_oss_url = params[:processed_oss_url].to_s.strip
				return render_error('processed_oss_url 不能为空') if processed_oss_url.blank?
				move_video.mark_processed!(processed_oss_url)
				render_success(message: '剪映完成已记录，已创建发布任务')
			elsif status == 'error'
				move_video.mark_jianying_failed!("剪映失败：#{params[:error_msg].to_s}")
				render_success(message: '剪映失败已记录')
			else
				render_error('status 必须为 success 或 error')
			end
		end

		# ---------- 5.5 混剪结果回传（mashup 混剪程序）----------
		# POST /api/v1/move_videos/report_merge_result
		# 入参：video_ids(1~2 个 move_video id 数组)、status(success|error)、
		#       processed_oss_url / title / description / platforms(success 时)、error_msg(error 时)
		# success：按 platforms 每平台建一条 hunjian_task，源视频置「混剪完成」；幂等（已入库忽略并回 success）
		# error：源视频退回「待混剪」（可重新领取），接受单条 video_ids
		def report_merge_result
			video_ids = params[:video_ids]
			video_ids = JSON.parse(video_ids) if video_ids.is_a?(String)
			unless video_ids.is_a?(Array) && video_ids.size.between?(1, 2) && video_ids.map(&:to_i).uniq.size == video_ids.size
				return render_error('video_ids 必须是 1~2 个不同的 id')
			end

			videos = video_ids.map { |id| MoveVideo.find_by(id: id.to_i) }
			return render_error('video 必须都存在') if videos.any?(&:nil?)

			status = params[:status].to_s.strip
			if status == 'success'
				return render_error('video_ids 成功时必须传 2 个') unless videos.size == 2
				handle_merge_success(videos)
			elsif status == 'error'
				handle_merge_error(videos, params[:error_msg].to_s)
			else
				render_error('status 必须为 success 或 error')
			end
		end

		# ---------- 6. 远端批量回传处理结果 ----------
		# POST /api/v1/move_videos/report_result
		# 入参：items（数组），每项 { id, status('processed'|'failed'), oss_url(成片URL, processed时必填), error_msg(可选) }
		# 流程（逐条处理）：
		#   1. 更新 move_video 状态
		#   2. 若有 oss_url → 为 5 个平台分别 upsert move_task（title 从 themes 表按 theme 随机选取）
		#   3. 删除 raw_oss_url 对应的 OSS 文件
		def report_result
			items = params[:items]
			items = JSON.parse(items) if items.is_a?(String)
			return render_error('items 不能为空') unless items.is_a?(Array) && items.any?

			results = items.map { |item| process_report_item(item) }

			render_success(message: '批量处理完成', data: { results: results })
		end

		private

		# 混剪成功：源视频置「混剪完成」，按平台建 hunjian_task；幂等（全部已完成则忽略重复回传）
		def handle_merge_success(videos)
			processed_oss_url = params[:processed_oss_url].to_s.strip
			title = params[:title].to_s.strip
			description = params[:description].to_s.strip
			platforms = params[:platforms].to_s.strip

			return render_error('processed_oss_url 不能为空') if processed_oss_url.blank?
			return render_error('title 不能为空') if title.blank?

			v1 = videos.first
			platforms_str = platforms.present? ? platforms : v1.platforms.to_s

			# 幂等：若这批源视频此前已全部混剪完成（已入库），直接回 success，不重复建任务
			if videos.all?(&:hunjian_completed?)
				return render_success(message: '已入库，忽略重复回传')
			end

			MoveVideo.transaction do
				videos.each do |v|
					v.update!(hunjian_status: :completed, error_msg: nil) unless v.hunjian_completed?
				end
				HunjianTask.create_from_hunjian_result!(
					move_video_ids: videos.map(&:id),
					oss_url: processed_oss_url,
					title: title,
					description: description,
					platforms: platforms_str,
					theme: v1.theme,
					group_id: v1.group_id
				)
			end

			# 事务提交后删除源视频 raw OSS 文件（失败不影响主流程）
			videos.each { |v| delete_raw_oss_file(v) }

			render_success(message: '混剪完成已记录，已创建发布任务')
		end

		# 混剪失败：源视频退回「待混剪」（可重新领取重试），接受单条
		def handle_merge_error(videos, error_msg)
			videos.each do |v|
				v.update!(
					hunjian_status: :pending,
					process_started_at: nil,
					error_msg: error_msg.presence || '混剪失败'
				)
			end
			render_success(message: '混剪失败已记录，源视频已退回待混剪')
		end

		# 处理单条回传数据
		def process_report_item(item)
			move_video = MoveVideo.find_by(id: item['id'])
			return { id: item['id'], success: false, error: '视频不存在' } unless move_video

			status = item['status'].to_s.strip
			unless %w[processed failed].include?(status)
				return { id: move_video.id, success: false, error: 'status 必须为 processed 或 failed' }
			end

			oss_url = item['oss_url'].to_s.strip
			if status == 'processed' && oss_url.blank?
				return { id: move_video.id, success: false, error: 'oss_url 不能为空' }
			end

			ActiveRecord::Base.transaction do
				if status == 'processed'
					move_video.update!(jianying_status: :completed, processed_at: Time.current, error_msg: nil)

					# 从 themes 表按 theme 名称查找待选标题
					theme_titles = Theme.find_by(name: move_video.theme)&.titles_array || []

					# 为 5 个平台分别创建/更新 move_task
					MoveTask.platforms.each_key do |platform_name|
						move_task = MoveTask.find_or_initialize_by(move_video_id: move_video.id, platform: platform_name)
						is_new = move_task.new_record?
						
						# 处理标题：youtube 平台如果超过 99 字符则截断
						title = theme_titles.empty? ? move_task.title : theme_titles.sample
						description = nil
						if platform_name == "youtube" && title.present? && title.length > 99
							description = title[99..]
							title = title[0...99]
						end
						
						move_task.assign_attributes(
							oss_url: oss_url,
							title: title,
							description: description,
							theme: move_video.theme,
							group_id: move_video.group_id
						)
						move_task.status = :pending if is_new
						move_task.save!
					end
				else
					move_video.update!(jianying_status: :failed, error_msg: item['error_msg'].to_s)
				end
			end

			if status == 'processed'
				# 事务提交后删除 raw OSS 文件（失败不影响主流程）
				delete_raw_oss_file(move_video)
			end

			{ id: move_video.id, success: true, jianying_status: move_video.jianying_status }
		rescue => e
			{ id: move_video&.id, success: false, error: e.message }
		end

		# 删除 raw_oss_url 对应的 OSS 文件
		def delete_raw_oss_file(move_video)
			return if move_video.raw_oss_url.blank?
			delete_oss_object_by_url(move_video.raw_oss_url, OSS_BUCKET)
			Rails.logger.info "[MoveVideo##{move_video.id}] 已删除 raw OSS 文件"
		rescue => e
			Rails.logger.error "[MoveVideo##{move_video.id}] 删除 raw OSS 文件失败: #{e.message}"
		end

			def find_move_video
				move_video = MoveVideo.find_by(id: params[:id])
				render_error('视频不存在') unless move_video
				move_video
			end

			# 还原丢失了分隔符的下载路径：
			# 下载软件回传 "C:UsersAdministratorDesktopvideosxxx.mp4"（/ 被剔除）
			# 剥离标准目录前缀（无斜杠形式）得到文件名，再拼回标准路径 "C:/Users/.../xxx.mp4"
			def normalize_download_path(path)
				base_without_slashes = DOWNLOAD_STANDARD_DIR.delete('/')
				filename = path.sub(/\A#{Regexp.escape(base_without_slashes)}/i, '')
				"#{DOWNLOAD_STANDARD_DIR}#{filename}"
			end

			def build_download_payload(move_video)
				{
					id: move_video.id,
					video_url: move_video.source_video_url,
					source_account_url: move_video.source_account_url,
					theme: move_video.theme,
					group_id: move_video.group_id
				}
			end

			# 不指定主题时：遍历所有有 pending_process 的主题，每个主题各取 limit_per_theme 条
			def pending_process_candidates_across_themes(limit_per_theme)
				themes = MoveVideo.pending_process.where.not(theme: [nil, '']).distinct.pluck(:theme).sort
				themes.flat_map do |t|
					MoveVideo.pending_process.where(theme: t).order(created_at: :asc).limit(limit_per_theme).to_a
				end
			end

			# 不指定主题时：遍历所有有「待混剪」的主题，每个主题各取 limit_per_theme 条
			def pending_hunjian_candidates_across_themes(limit_per_theme)
				themes = MoveVideo.pending_hunjian.where.not(theme: [nil, '']).distinct.pluck(:theme).sort
				themes.flat_map do |t|
					MoveVideo.pending_hunjian.where(theme: t).order(created_at: :asc).limit(limit_per_theme).to_a
				end
			end

			# 组装单条待处理视频的返回结构
			def build_pending_process_item(video)
				{
					id: video.id,
					theme: video.theme,
					group_id: video.group_id,
					raw_oss_url: video.raw_oss_url,
					source_title: video.source_title,
					source_video_url: video.source_video_url,
					platforms: video.platforms
				}
			end

			def render_success(data: nil, message: 'success')
				resp = { type: 'success' }
				resp[:data] = data if data
				resp[:message] = message
				render json: resp
			end

			def render_error(message)
				render json: { type: 'error', message: message }
			end

			def render_state_error(error)
				render json: { type: 'error', message: error.message }
			end
		end
	end
end
