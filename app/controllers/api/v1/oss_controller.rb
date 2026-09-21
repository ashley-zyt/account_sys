module Api
	module V1
		# OSS 直传签名接口：调用方（机器端 / 本地脚本）用自己的本地视频文件直传到 OSS，Secret 不出服务器。
		#
		# 流程：
		#   1. 调用方 POST /api/v1/oss/upload_signature 拿上传凭证（policy/signature/key/endpoint/accessKeyId）
		#   2. 调用方把本地文件用 multipart POST 直接传到 endpoint（不经过 account_sys）
		#   3. 上传完成后，直接用返回的 url（下载签名 URL）访问视频
		class OssController < ApplicationController
			# 外部 API 调用，关闭 CSRF 校验
			skip_forgery_protection

			include OssSignedUrl

			# 默认上传到运营视频 bucket
			DEFAULT_BUCKET = 'operation-viodes'.freeze
			# 上传凭证有效期：1 小时（拿到凭证后需在此时间内完成上传）
			POLICY_EXPIRES_IN = 3600
			# 下载签名 URL 默认有效期：半年（180 天 = 15552000 秒）
			DEFAULT_URL_EXPIRES_IN = 180 * 24 * 60 * 60
			# 文件大小上限：500MB
			MAX_SIZE = 500 * 1024 * 1024

			# POST /api/v1/oss/upload_signature
			# 入参：
			#   filename        可选，原始文件名（用于提取扩展名生成 key）
			#   bucket          可选，OSS bucket，默认 operation-viodes
			#   url_expires_in  可选，下载签名 URL 有效期（秒），默认半年
			# 返回 data：
			#   bucket / key / endpoint / accessKeyId / policy / signature / expire
			#   url（下载签名 URL，上传完成后即可访问）/ url_expires_at
			def upload_signature
				filename       = params[:filename].to_s.strip
				bucket         = params[:bucket].presence || DEFAULT_BUCKET
				url_expires_in = (params[:url_expires_in].presence || DEFAULT_URL_EXPIRES_IN).to_i

				return render_error('OSS 凭证未配置') unless oss_credentials_configured?
				return render_error('url_expires_in 必须为正整数') if url_expires_in <= 0

				access_key_id = ENV['ALIYUN_ACCESS_KEY_ID']
				access_key_secret = ENV['ALIYUN_ACCESS_KEY_SECRET']

				# key = UUID + 原扩展名，放在 bucket 根目录
				ext = filename.present? ? File.extname(filename) : ''
				key = "#{SecureRandom.uuid}#{ext}"

				sig = generate_post_object_signature(
					bucket, key, access_key_id, access_key_secret,
					policy_expires_in: POLICY_EXPIRES_IN, max_size: MAX_SIZE
				)

				# 下载签名 URL（对 key 的访问授权，文件传上去后即可用）
				download_url = generate_oss_signed_url(bucket, key, access_key_id, access_key_secret, expires_in: url_expires_in)

				render json: {
					type: 'success',
					message: '签名生成成功',
					data: {
						bucket: bucket,
						key: key,
						endpoint: "https://#{bucket}.oss-cn-hangzhou.aliyuncs.com",
						accessKeyId: access_key_id,
						policy: sig[:policy],
						signature: sig[:signature],
						expire: sig[:expire],
						url: download_url,
						url_expires_at: (Time.now + url_expires_in).iso8601
					}
				}
			end

			private

			def render_error(message)
				render json: { type: 'error', message: message }
			end
		end
	end
end
