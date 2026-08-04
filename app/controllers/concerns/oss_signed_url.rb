require 'net/http'
require 'openssl'
require 'base64'

# OSS 签名 URL 工具：校验对象存在 + 生成 GET 签名 URL
# 供 GrokController / MoveVideosController 等共用，避免各控制器重复实现
module OssSignedUrl
	extend ActiveSupport::Concern

	OSS_REGION_HOST = 'oss-cn-hangzhou.aliyuncs.com'.freeze

	private

	# OSS 凭证是否已配置
	def oss_credentials_configured?
		ENV['ALIYUN_ACCESS_KEY_ID'].present? && ENV['ALIYUN_ACCESS_KEY_SECRET'].present?
	end

	# 从路径/URL 解析文件名（兼容 URL / Linux / Windows 路径）
	def parse_oss_filename(path)
		path.to_s.split('?').first.split(/[\/\\]/).last.to_s
	end

	# 校验 OSS 对象是否存在（HEAD 请求，签名基于 Date）
	def oss_object_exists?(bucket_name, key, access_key_id, access_key_secret)
		date = Time.now.utc.strftime('%a, %d %b %Y %H:%M:%S GMT')

		# 签名字符串中的 key 使用原始路径（不编码）
		string_to_sign = "HEAD\n\n\n#{date}\n/#{bucket_name}/#{key}"
		signature = Base64.strict_encode64(
			OpenSSL::HMAC.digest('sha1', access_key_secret, string_to_sign)
		).strip

		# URL 中的 key 需要编码
		encoded_key = URI.encode_www_form_component(key)
		uri = URI.parse("https://#{bucket_name}.#{OSS_REGION_HOST}/#{encoded_key}")
		http = Net::HTTP.new(uri.host, uri.port)
		http.use_ssl = true
		http.verify_mode = OpenSSL::SSL::VERIFY_NONE

		request = Net::HTTP::Head.new(uri.request_uri)
		request['Date'] = date
		request['Authorization'] = "OSS #{access_key_id}:#{signature}"

		response = http.request(request)
		response.code == '200'
	end

	# 生成 OSS GET 签名 URL（签名基于 Expires，1 年有效期）
	def generate_oss_signed_url(bucket_name, key, access_key_id, access_key_secret)
		ts = Time.now.to_i + 31536000 # 1年有效期

		# 签名字符串中的 key 使用原始路径（不编码）
		cano_res = "/#{bucket_name}/#{key}"
		sign_string = "GET\n\n\n#{ts}\n#{cano_res}"

		signature = OpenSSL::HMAC.digest('sha1', access_key_secret, sign_string).to_s
		signature = Base64.strict_encode64(signature).strip
		signature = URI.encode_www_form_component(signature)

		# URL 中的 key 需要编码
		encoded_key = URI.encode_www_form_component(key)

		"https://#{bucket_name}.#{OSS_REGION_HOST}/#{encoded_key}?OSSAccessKeyId=#{access_key_id}&Expires=#{ts}&Signature=#{signature}"
	end

	# 一站式：传入 path + bucket，解析文件名 → 校验存在 → 生成签名 URL
	# @return [Hash] 成功 { ok: true, signed_url:, bucket:, filename: }
	#                失败 { ok: false, reason: :invalid_filename|:no_credentials|:not_found, error: '...' }
	def resolve_oss_signed_url(path, bucket_name)
		filename = parse_oss_filename(path)
		return { ok: false, reason: :invalid_filename, error: '无法从路径中解析出文件名' } if filename.blank?
		return { ok: false, reason: :no_credentials, error: 'OSS 凭证未配置' } unless oss_credentials_configured?

		access_key_id = ENV['ALIYUN_ACCESS_KEY_ID']
		access_key_secret = ENV['ALIYUN_ACCESS_KEY_SECRET']

		return { ok: false, reason: :not_found, error: '视频文件在 OSS 中不存在' } unless oss_object_exists?(bucket_name, filename, access_key_id, access_key_secret)

		signed_url = generate_oss_signed_url(bucket_name, filename, access_key_id, access_key_secret)
		{ ok: true, signed_url: signed_url, bucket: bucket_name, filename: filename }
	end

	# 生成随机不重复文件名（UUID + 原扩展名）
	def generate_random_oss_filename(original_filename)
		ext = File.extname(original_filename).to_s.downcase
		"#{SecureRandom.uuid}#{ext}"
	end

	# OSS CopyObject：同 bucket 内复制对象（PUT + x-oss-copy-source）
	def oss_copy_object?(bucket_name, source_key, target_key, access_key_id, access_key_secret)
		date = Time.now.utc.strftime('%a, %d %b %Y %H:%M:%S GMT')
		copy_source = "/#{bucket_name}/#{source_key}"
		# CanonicalizedOSSHeaders 须参与签名：x-oss-copy-source:值\n
		string_to_sign = "PUT\n\n\n#{date}\nx-oss-copy-source:#{copy_source}\n/#{bucket_name}/#{target_key}"
		signature = Base64.strict_encode64(
			OpenSSL::HMAC.digest('sha1', access_key_secret, string_to_sign)
		).strip

		encoded_target = URI.encode_www_form_component(target_key)
		uri = URI.parse("https://#{bucket_name}.#{OSS_REGION_HOST}/#{encoded_target}")
		http = Net::HTTP.new(uri.host, uri.port)
		http.use_ssl = true
		http.verify_mode = OpenSSL::SSL::VERIFY_NONE

		request = Net::HTTP::Put.new(uri.request_uri)
		request['Date'] = date
		request['Authorization'] = "OSS #{access_key_id}:#{signature}"
		request['x-oss-copy-source'] = copy_source

		response = http.request(request)
		response.code == '200'
	end

	# OSS DeleteObject
	def oss_delete_object?(bucket_name, key, access_key_id, access_key_secret)
		date = Time.now.utc.strftime('%a, %d %b %Y %H:%M:%S GMT')
		string_to_sign = "DELETE\n\n\n#{date}\n/#{bucket_name}/#{key}"
		signature = Base64.strict_encode64(
			OpenSSL::HMAC.digest('sha1', access_key_secret, string_to_sign)
		).strip

		encoded_key = URI.encode_www_form_component(key)
		uri = URI.parse("https://#{bucket_name}.#{OSS_REGION_HOST}/#{encoded_key}")
		http = Net::HTTP.new(uri.host, uri.port)
		http.use_ssl = true
		http.verify_mode = OpenSSL::SSL::VERIFY_NONE

		request = Net::HTTP::Delete.new(uri.request_uri)
		request['Date'] = date
		request['Authorization'] = "OSS #{access_key_id}:#{signature}"

		response = http.request(request)
		response.code == '204'
	end

	# 与 resolve_oss_signed_url 类似，但会把 OSS 文件重命名为随机不重复文件名（复制到新名 + 删除原文件）
	# 用于下载转存场景，避免文件名冲突并生成规范文件名
	# @return [Hash] 成功 { ok: true, signed_url:, bucket:, filename: (新文件名), original_filename: }
	#                失败 { ok: false, reason: :invalid_filename|:no_credentials|:not_found|:copy_failed, error: }
	def resolve_and_rename_oss_signed_url(path, bucket_name)
		filename = parse_oss_filename(path)
		return { ok: false, reason: :invalid_filename, error: '无法从路径中解析出文件名' } if filename.blank?
		return { ok: false, reason: :no_credentials, error: 'OSS 凭证未配置' } unless oss_credentials_configured?

		access_key_id = ENV['ALIYUN_ACCESS_KEY_ID']
		access_key_secret = ENV['ALIYUN_ACCESS_KEY_SECRET']

		return { ok: false, reason: :not_found, error: '视频文件在 OSS 中不存在' } unless oss_object_exists?(bucket_name, filename, access_key_id, access_key_secret)

		# 生成随机不重复文件名（保留原扩展名）
		new_filename = generate_random_oss_filename(filename)

		# 复制到新文件名
		return { ok: false, reason: :copy_failed, error: 'OSS 文件复制失败' } unless oss_copy_object?(bucket_name, filename, new_filename, access_key_id, access_key_secret)

		# 删除原文件（失败不影响主流程，仅告警；新文件已就位）
		unless oss_delete_object?(bucket_name, filename, access_key_id, access_key_secret)
			warn "OSS 原文件删除失败：#{filename}（已复制为 #{new_filename}）"
		end

		signed_url = generate_oss_signed_url(bucket_name, new_filename, access_key_id, access_key_secret)
		{ ok: true, signed_url: signed_url, bucket: bucket_name, filename: new_filename, original_filename: filename }
	end
end
