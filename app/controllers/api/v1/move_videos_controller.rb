module Api
	module V1
		# 搬运视频资源接口（下载转存 + 剪映处理）
		#
		# 流程：
		#   import            录入源视频 → move_video(pending_download)
		#   fetch_for_download   下载软件拉取 → downloading
		#   report_download      下载完成回传 raw_oss_url → pending_process
		#   fetch_for_processing 剪映项目拉取 → processing
		#   report_processing    剪映完成回传 processed_oss_url → processed + 创建多平台 move_task
		class MoveVideosController < ApplicationController
			skip_before_action :verify_authenticity_token
			rescue_from MoveVideo::StateError, with: :render_state_error

			DEFAULT_PLATFORMS_STR = MoveVideo::DEFAULT_PLATFORMS.join(',')

			# ---------- 1. 录入源视频 ----------
			# POST /api/v1/move_videos/import
			# 入参：source_url(来源账号主页链接)、video_url(源视频链接)、platforms(可选，逗号分隔)
			# 主题由 ThemeConfig 按 source_url 匹配；幂等：同一 video_url 重复录入返回已存在记录
			def import
				source_url = params[:source_url].to_s.strip
				video_url  = params[:video_url].to_s.strip
				platforms  = params[:platforms].to_s.strip

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
						platforms: platforms_str
					)
				rescue ActiveRecord::RecordNotUnique
					# 并发下同 video_url 重复创建，直接取已存在记录
					move_video = MoveVideo.find_by!(source_video_url: video_url)
					existed = true
				end

				render_success(data: {
					id: move_video.id,
					video_url: move_video.source_video_url,
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

			# ---------- 3. 下载完成回调 ----------
			# POST /api/v1/move_videos/report_download
			# 入参：id、status('success'|'error')、raw_oss_url、error_msg
			def report_download
				move_video = find_move_video
				return unless move_video

				status = params[:status].to_s.strip
				if status == 'success'
					raw_oss_url = params[:raw_oss_url].to_s.strip
					return render_error('raw_oss_url 不能为空') if raw_oss_url.blank?
					move_video.mark_downloaded!(raw_oss_url)
					render_success(message: '下载完成已记录')
				elsif status == 'error'
					move_video.mark_failed!("下载失败：#{params[:error_msg].to_s}")
					render_success(message: '下载失败已记录')
				else
					render_error('status 必须为 success 或 error')
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
					move_video.mark_failed!("剪映失败：#{params[:error_msg].to_s}")
					render_success(message: '剪映失败已记录')
				else
					render_error('status 必须为 success 或 error')
				end
			end

			private

			def find_move_video
				move_video = MoveVideo.find_by(id: params[:id])
				render_error('视频不存在') unless move_video
				move_video
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
