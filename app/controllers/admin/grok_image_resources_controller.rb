class Admin::GrokImageResourcesController < Admin::BaseController
  # 配置 OSS CORS 规则（只需执行一次）
  def setup_cors
    require 'net/http'
    require 'uri'
    require 'openssl'
    require 'base64'
    require 'digest/md5'

    access_key_id = ENV['ALIYUN_ACCESS_KEY_ID']
    access_key_secret = ENV['ALIYUN_ACCESS_KEY_SECRET']
    bucket_name = 'grok-images'

    raise "ALIYUN_ACCESS_KEY_ID 未配置" if access_key_id.blank?
    raise "ALIYUN_ACCESS_KEY_SECRET 未配置" if access_key_secret.blank?

    endpoint = "https://#{bucket_name}.oss-cn-hangzhou.aliyuncs.com"

    # CORS 配置 XML
    cors_xml = <<-XML
<?xml version="1.0" encoding="UTF-8"?>
<CORSConfiguration>
  <CORSRule>
    <AllowedOrigin>*</AllowedOrigin>
    <AllowedMethod>GET</AllowedMethod>
    <AllowedMethod>POST</AllowedMethod>
    <AllowedMethod>HEAD</AllowedMethod>
    <AllowedHeader>*</AllowedHeader>
    <ExposeHeader>ETag</ExposeHeader>
    <ExposeHeader>x-oss-request-id</ExposeHeader>
    <MaxAgeSeconds>3600</MaxAgeSeconds>
  </CORSRule>
</CORSConfiguration>
XML

    # 生成签名
    date = Time.now.utc.strftime('%a, %d %b %Y %H:%M:%S GMT')
    content_md5 = Base64.strict_encode64(Digest::MD5.digest(cors_xml)).strip

    # 签名字符串：PUT + MD5 + Content-Type + Date + Resource
    string_to_sign = "PUT\n#{content_md5}\napplication/xml\n#{date}\n/#{bucket_name}/?cors"

    # 使用 HMAC-SHA1 签名
    signature = Base64.strict_encode64(
      OpenSSL::HMAC.digest('sha1', access_key_secret, string_to_sign)
    ).strip

    # 发送请求
    uri = URI.parse("#{endpoint}/?cors")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    request = Net::HTTP::Put.new(uri.request_uri)
    request['Date'] = date
    request['Content-Type'] = 'application/xml'
    request['Content-MD5'] = content_md5
    request['Authorization'] = "OSS #{access_key_id}:#{signature}"
    request.body = cors_xml

    response = http.request(request)

    if response.code == '200'
      render json: { success: true, message: 'CORS 规则配置成功' }
    else
      render json: { success: false, error: "配置失败: #{response.code} - #{response.body}" }, status: :unprocessable_entity
    end
  rescue => e
    render json: { success: false, error: e.message }, status: :unprocessable_entity
  end

  # OSS 直传签名接口（bucket: grok-images）
  def oss_signature
    require 'base64'
    require 'json'
    require 'openssl'

    endpoint = 'https://oss-cn-hangzhou.aliyuncs.com'
    access_key_id = ENV['ALIYUN_ACCESS_KEY_ID']
    access_key_secret = ENV['ALIYUN_ACCESS_KEY_SECRET']
    bucket_name = 'grok-images'

    raise "ALIYUN_ACCESS_KEY_ID 未配置" if access_key_id.blank?
    raise "ALIYUN_ACCESS_KEY_SECRET 未配置" if access_key_secret.blank?

    filename = params[:filename]

    # 生成文件名（UUID + 时间戳，保留扩展名），直接放在 bucket 根目录
    if filename.present?
      ext = File.extname(filename)
      key = "#{SecureRandom.uuid}_#{Time.now.to_i}#{ext}"
    else
      key = "#{SecureRandom.uuid}_#{Time.now.to_i}"
    end

    # 过期时间：30天
    expire_time = Time.now.to_i + 2592000

    # 构建 Policy
    policy = {
      expiration: Time.at(expire_time).utc.iso8601,
      conditions: [
        { bucket: bucket_name },
        { key: key },
        ['content-length-range', 0, 50 * 1024 * 1024] # 图片最大 50MB
      ]
    }

    # Base64 编码 Policy
    policy_base64 = Base64.strict_encode64(policy.to_json)

    # 生成签名
    signature = OpenSSL::HMAC.digest('sha1', access_key_secret, policy_base64)
    signature = Base64.strict_encode64(signature)

    render json: {
      accessKeyId: access_key_id,
      policy: policy_base64,
      signature: signature,
      bucket: bucket_name,
      endpoint: "https://#{bucket_name}.oss-cn-hangzhou.aliyuncs.com",
      key: key,
      expire: expire_time
    }
  end

  def index
    @q = GrokImageResource.ransack(params[:q])
    @grok_image_resources = @q.result
                              .includes(:video_tasks)
                              .order(created_at: :desc)
                              .page(params[:page])
  end

  def new
    @grok_image_resource = GrokImageResource.new
    @themes = Theme.pluck(:name)
  end

  def create
    # 前端直传 OSS 后，提交 oss_keys（支持多张），后端为每个 key 生成签名 URL 存入 image_url
    oss_keys = params[:oss_keys].presence
    oss_keys = [oss_keys] if oss_keys.is_a?(String)

    if oss_keys.present?
      theme = grok_image_resource_params[:theme]
      image_name = grok_image_resource_params[:image_name]
      success_count = 0
      first_resource = nil

      oss_keys.compact_blank.each do |oss_key|
        image_url = generate_signed_url(oss_key)
        resource = GrokImageResource.new(theme: theme, image_url: image_url, image_name: image_name)
        if resource.save
          success_count += 1
          first_resource ||= resource
        end
      end

      if success_count > 0
        redirect_to admin_grok_image_resources_path,
                    notice: "成功添加 #{success_count} 张图片#{oss_keys.compact_blank.size > success_count ? "（部分失败）" : ''}"
      else
        @grok_image_resource = GrokImageResource.new(theme: theme)
        @grok_image_resource.errors.add(:base, '图片保存失败，请重试')
        @themes = Theme.pluck(:name)
        render :new, status: :unprocessable_entity
      end
    else
      @grok_image_resource = GrokImageResource.new(grok_image_resource_params)
      @themes = Theme.pluck(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @grok_image_resource = GrokImageResource.find(params[:id])

    # 从 image_url 提取 OSS key 并删除 OSS 文件
    delete_oss_object(@grok_image_resource.image_url)

    @grok_image_resource.destroy
    redirect_to admin_grok_image_resources_path, notice: '图片储备删除成功'
  end

  private

  # 从签名 URL 中提取 OSS key 并调用 OSS REST API 删除文件
  def delete_oss_object(image_url)
    return if image_url.blank?

    require 'net/http'
    require 'uri'
    require 'openssl'
    require 'base64'

    access_key_id = ENV['ALIYUN_ACCESS_KEY_ID']
    access_key_secret = ENV['ALIYUN_ACCESS_KEY_SECRET']
    bucket_name = 'grok-images'

    # URL: https://bucket.oss-cn-hangzhou.aliyuncs.com/encoded_key?OSSAccessKeyId=...
    uri = URI.parse(image_url)
    encoded_key = uri.path.sub(%r{^/}, '')  # 去掉前导 /
    key = URI.decode_www_form_component(encoded_key) rescue encoded_key

    date = Time.now.utc.strftime('%a, %d %b %Y %H:%M:%S GMT')

    # 签名字符串：DELETE + 空 + 空 + Date + Resource
    string_to_sign = "DELETE\n\n\n#{date}\n/#{bucket_name}/#{key}"
    signature = Base64.strict_encode64(
      OpenSSL::HMAC.digest('sha1', access_key_secret, string_to_sign)
    ).strip

    oss_uri = URI.parse("https://#{bucket_name}.oss-cn-hangzhou.aliyuncs.com/#{encoded_key}")
    http = Net::HTTP.new(oss_uri.host, oss_uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    request = Net::HTTP::Delete.new(oss_uri.request_uri)
    request['Date'] = date
    request['Authorization'] = "OSS #{access_key_id}:#{signature}"

    http.request(request)
  rescue => e
    Rails.logger.error "OSS 删除失败: #{e.message}"
  end

  def grok_image_resource_params
    params.require(:grok_image_resource).permit(:theme, :image_url, :image_name)
  end

  # 生成 OSS 签名 URL（bucket: grok-images，1年有效期）
  def generate_signed_url(key)
    require 'base64'
    require 'openssl'

    access_key_id = ENV['ALIYUN_ACCESS_KEY_ID']
    access_key_secret = ENV['ALIYUN_ACCESS_KEY_SECRET']
    bucket_name = 'grok-images'

    verb = "GET"
    content_md5 = ""
    content_type = ""
    ts = (Time.now.to_i + 31536000) # 1年有效期

    # 签名字符串中的 key 使用原始路径（不编码）
    cano_res = "/#{bucket_name}/#{key}"
    sign_string = "#{verb}\n#{content_md5}\n#{content_type}\n#{ts}\n#{cano_res}"

    # 生成签名
    signature = OpenSSL::HMAC.digest("sha1", access_key_secret, sign_string).to_s
    signature = Base64.strict_encode64(signature).strip
    signature = URI.encode_www_form_component(signature)

    # URL 中的 key 需要编码
    encoded_key = URI.encode_www_form_component(key)

    "https://#{bucket_name}.oss-cn-hangzhou.aliyuncs.com/#{encoded_key}?OSSAccessKeyId=#{access_key_id}&Expires=#{ts}&Signature=#{signature}"
  end
end
