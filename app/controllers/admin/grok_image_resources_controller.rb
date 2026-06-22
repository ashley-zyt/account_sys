class Admin::GrokImageResourcesController < Admin::BaseController
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
    @grok_image_resources = @q.result.order(created_at: :desc).page(params[:page])
  end

  def new
    @grok_image_resource = GrokImageResource.new
    @themes = Theme.pluck(:name)
  end

  def create
    # 前端直传 OSS 后，提交 oss_key，后端生成签名 URL 存入 image_url
    if params[:oss_key].present?
      theme = grok_image_resource_params[:theme]
      image_url = generate_signed_url(params[:oss_key])

      @grok_image_resource = GrokImageResource.new(theme: theme, image_url: image_url)

      if @grok_image_resource.save
        redirect_to admin_grok_image_resources_path, notice: '图片储备添加成功'
      else
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
    @grok_image_resource.destroy
    redirect_to admin_grok_image_resources_path, notice: '图片储备删除成功'
  end

  private

  def grok_image_resource_params
    params.require(:grok_image_resource).permit(:theme, :image_url)
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
