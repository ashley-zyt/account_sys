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
end
