module Api
	module V1
		# 通用 OSS 上传接口：把服务器本地视频文件上传到 OSS bucket，返回带签名的访问链接
		#
		# 场景：视频已经落在 account_sys 服务器本机磁盘上（如机器端下载/生成后放到共享目录），
		# 由本接口读取本地路径并转存到 OSS，调用方拿到签名 URL 直接使用。
		class OssController < ApplicationController
			# 外部 API 调用，关闭 CSRF 校验
			skip_forgery_protection

			include OssSignedUrl

			# 默认上传到运营视频 bucket
			DEFAULT_BUCKET = 'operation-viodes'.freeze
			# 签名 URL 默认有效期：半年（180 天 = 15552000 秒）
			DEFAULT_EXPIRES_IN = 180 * 24 * 60 * 60

			# POST /api/v1/oss/upload_video
			# 入参：
			#   path        必填，本地视频文件的绝对路径（如 /data/videos/xxx.mp4）
			#   bucket      可选，OSS bucket 名称，默认 operation-viodes
			#   expires_in  可选，签名 URL 有效期（秒），默认半年（180 天）
			# 返回：
			#   成功 { type: 'success', message: '视频上传成功',
			#          data: { key:, url:, bucket:, filename:, expires_at: } }
			#   失败 { type: 'error', message: '...' }
			def upload_video
				path       = params[:path].to_s.strip
				bucket     = params[:bucket].presence || DEFAULT_BUCKET
				expires_in = (params[:expires_in].presence || DEFAULT_EXPIRES_IN).to_i

				return render_error('path 不能为空') if path.blank?
				return render_error('expires_in 必须为正整数') if expires_in <= 0

				result = upload_local_file_to_oss(path, bucket, expires_in: expires_in)

				if result[:ok]
					render json: {
						type: 'success',
						message: '视频上传成功',
						data: {
							key: result[:key],
							url: result[:signed_url],
							bucket: result[:bucket],
							filename: result[:filename],
							expires_at: result[:expires_at].iso8601
						}
					}
				else
					render_error(result[:error])
				end
			end

			private

			def render_error(message)
				render json: { type: 'error', message: message }
			end
		end
	end
end
