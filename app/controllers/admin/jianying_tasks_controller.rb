class Admin::JianyingTasksController < Admin::BaseController
	before_action :set_jianying_task, only: [:show, :destroy]

	OSS_BUCKET = "jianying-rd".freeze
	OSS_REGION = "cn-hangzhou".freeze
	OSS_ACCESS_KEY_ID = "gZL8z938T19mSUHf".freeze
	OSS_ACCESS_KEY_SECRET = "A9fSDa9cH5YAExpEUR4QSizkFQEcrS".freeze

	def index
		@q = JianyingTask.ransack(params[:q])
		@jianying_tasks = @q.result(distinct: true)
		                   .order(created_at: :desc)
		                   .page(params[:page])
		                   .per(15)
	end

	def show
		@image_names = parse_image_names(@jianying_task)
		@image_urls  = build_oss_image_urls(@jianying_task, @image_names)
		@video_url   = oss_v4_sign_url(@jianying_task.oss_url)
	end

	def destroy
		if @jianying_task.pending?
			@jianying_task.destroy
			redirect_to admin_jianying_tasks_path, notice: "任务删除成功"
		else
			redirect_to admin_jianying_tasks_path, alert: "仅待分配状态的任务可以删除"
		end
	end

	private

	def set_jianying_task
		@jianying_task = JianyingTask.find(params[:id])
	end

	def parse_image_names(task)
		JSON.parse(task.associated_images) rescue []
	end

	def build_oss_image_urls(task, names)
		return [] unless names.is_a?(Array) && names.any?
		names.map do |name|
			key = "#{task.keyword_code}/#{name}"
			{ name: name, key: key, url: oss_v4_sign_url(key) }
		end
	end

	# OSS V4 预签名 URL（GET，HMAC-SHA256）
	def oss_v4_sign_url(key)
		return nil if key.blank?
		require "openssl"

		now = Time.now.utc
		date_stamp = now.strftime("%Y%m%d")
		timestamp  = now.strftime("%Y%m%dT%H%M%SZ")
		credential = "#{OSS_ACCESS_KEY_ID}/#{date_stamp}/#{OSS_REGION}/oss/aliyun_v4_request"

		canonical_query = [
			"x-oss-credential=#{percent_encode(credential)}",
			"x-oss-date=#{timestamp}",
			"x-oss-expires=3600",
			"x-oss-signature-version=OSS4-HMAC-SHA256"
		].join("&")

		canonical_uri = percent_encode_path("/#{key}")
		canonical_request = ["GET", canonical_uri, canonical_query, "", "", "UNSIGNED-PAYLOAD"].join("\n")
		hashed = Digest::SHA256.hexdigest(canonical_request)

		scope = "#{date_stamp}/#{OSS_REGION}/oss/aliyun_v4_request"
		string_to_sign = ["OSS4-HMAC-SHA256", timestamp, scope, hashed].join("\n")

		k_date    = OpenSSL::HMAC.digest("sha256", "aliyun_v4#{OSS_ACCESS_KEY_SECRET}", date_stamp)
		k_region  = OpenSSL::HMAC.digest("sha256", k_date, OSS_REGION)
		k_service = OpenSSL::HMAC.digest("sha256", k_region, "oss")
		k_signing = OpenSSL::HMAC.digest("sha256", k_service, "aliyun_v4_request")
		signature = OpenSSL::HMAC.hexdigest("sha256", k_signing, string_to_sign)

		encoded_key = key.split("/").map { |seg| percent_encode(seg) }.join("/")
		"https://#{OSS_BUCKET}.oss-#{OSS_REGION}.aliyuncs.com/#{encoded_key}?" \
			"x-oss-credential=#{percent_encode(credential)}" \
			"&x-oss-date=#{timestamp}" \
			"&x-oss-expires=3600" \
			"&x-oss-signature=#{signature}" \
			"&x-oss-signature-version=OSS4-HMAC-SHA256"
	end

	def percent_encode(str)
		URI.encode_www_form_component(str).gsub("+", "%20")
	end

	def percent_encode_path(path)
		path.split("/").map { |seg| percent_encode(seg) }.join("/")
	end
end
