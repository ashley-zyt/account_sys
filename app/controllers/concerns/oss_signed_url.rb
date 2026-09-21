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

	# 生成 OSS GET 签名 URL（签名基于 Expires）
	# expires_in：签名 URL 有效期（秒），默认 1 年（31536000）
	def generate_oss_signed_url(bucket_name, key, access_key_id, access_key_secret, expires_in: 31536000)
		ts = Time.now.to_i + expires_in

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

	# 从签名 URL 中提取 key 并删除 OSS 对象（DELETE 请求，V1 签名）
	# @param signed_url [String] OSS 签名 URL
	# @param bucket_name [String] OSS bucket 名称
	# @return [Boolean] 是否删除成功（404 视为已不存在，也算成功）
	def delete_oss_object_by_url(signed_url, bucket_name)
		return false if signed_url.blank?
		return false unless oss_credentials_configured?

		access_key_id = ENV['ALIYUN_ACCESS_KEY_ID']
		access_key_secret = ENV['ALIYUN_ACCESS_KEY_SECRET']

		uri = URI.parse(signed_url.to_s)
		encoded_key = uri.path.sub(%r{\A/}, '')
		return false if encoded_key.blank?

		# 签名字符串中的 key 使用解码后的原始路径
		key = URI.decode_www_form_component(encoded_key)

		date = Time.now.utc.strftime('%a, %d %b %Y %H:%M:%S GMT')
		string_to_sign = "DELETE\n\n\n#{date}\n/#{bucket_name}/#{key}"
		signature = Base64.strict_encode64(
			OpenSSL::HMAC.digest('sha1', access_key_secret, string_to_sign)
		).strip

		oss_uri = URI.parse("https://#{bucket_name}.#{OSS_REGION_HOST}/#{encoded_key}")
		http = Net::HTTP.new(oss_uri.host, oss_uri.port)
		http.use_ssl = true
		http.verify_mode = OpenSSL::SSL::VERIFY_NONE

		request = Net::HTTP::Delete.new(oss_uri.request_uri)
		request['Date'] = date
		request['Authorization'] = "OSS #{access_key_id}:#{signature}"

		response = http.request(request)
		['200', '204', '404'].include?(response.code)
	end

	# 将服务器本地文件上传到 OSS bucket，返回 OSS key + 签名 URL
	# 文件名用 UUID + 原扩展名，剔除原始文件名，避免同名冲突与路径泄露
	#
	# @param path [String] 本地文件绝对路径
	# @param bucket_name [String] OSS bucket 名称
	# @param expires_in [Integer] 签名 URL 有效期（秒），默认半年 15552000（180 天）
	# @return [Hash] 成功 { ok: true, key:, signed_url:, bucket:, filename:, expires_at: }
	#                失败 { ok: false, reason: :no_credentials|:invalid_path|:file_not_found|:upload_failed, error: '...' }
	def upload_local_file_to_oss(path, bucket_name, expires_in: 15552000)
		return { ok: false, reason: :no_credentials, error: 'OSS 凭证未配置' } unless oss_credentials_configured?

		path = path.to_s.strip
		return { ok: false, reason: :invalid_path, error: '本地文件路径不能为空' } if path.blank?
		return { ok: false, reason: :file_not_found, error: "本地文件不存在：#{path}" } unless File.file?(path)

		access_key_id = ENV['ALIYUN_ACCESS_KEY_ID']
		access_key_secret = ENV['ALIYUN_ACCESS_KEY_SECRET']

		# 用 UUID 作为 key（保留原扩展名），放在 bucket 根目录
		key = "#{SecureRandom.uuid}#{File.extname(path)}"

		require 'aliyun/oss'
		client = Aliyun::OSS::Client.new(
			endpoint: "https://#{OSS_REGION_HOST}",
			access_key_id: access_key_id,
			access_key_secret: access_key_secret
		)
		client.get_bucket(bucket_name).put_object(key, file: path)

		signed_url = generate_oss_signed_url(bucket_name, key, access_key_id, access_key_secret, expires_in: expires_in)

		{
			ok: true,
			key: key,
			signed_url: signed_url,
			bucket: bucket_name,
			filename: File.basename(path),
			expires_at: Time.now + expires_in
		}
	rescue => e
		{ ok: false, reason: :upload_failed, error: e.message }
	end

	# 生成 OSS PostObject 直传签名：客户端拿到后直接 multipart POST 到 OSS，无需 Secret。
	# policy 里对 bucket/key 做精确匹配，并限制文件大小。
	#
	# @param bucket_name [String] bucket 名
	# @param key [String] 上传后的对象 key（policy 精确匹配，客户端表单的 key 字段必须等于它）
	# @param policy_expires_in [Integer] 上传凭证有效期（秒），默认 1 小时
	# @param max_size [Integer] 文件大小上限（字节），默认 500MB
	# @return [Hash] { policy:, signature:, expire: }
	def generate_post_object_signature(bucket_name, key, access_key_id, access_key_secret, policy_expires_in: 3600, max_size: 500 * 1024 * 1024)
		require 'json'

		expire_time = Time.now.to_i + policy_expires_in

		policy = {
			expiration: Time.at(expire_time).utc.iso8601,
			conditions: [
				{ bucket: bucket_name },
				{ key: key },
				['content-length-range', 0, max_size]
			]
		}

		policy_base64 = Base64.strict_encode64(policy.to_json)
		signature = Base64.strict_encode64(
			OpenSSL::HMAC.digest('sha1', access_key_secret, policy_base64)
		)

		{ policy: policy_base64, signature: signature, expire: expire_time }
	end
end
