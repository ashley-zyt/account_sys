class Admin::OperationTasksController < Admin::BaseController
  before_action :set_operation_task, only: [:show, :destroy]
  
  # 配置 OSS CORS 规则（只需执行一次）
  def setup_cors
    require 'net/http'
    require 'uri'
    require 'openssl'
    require 'base64'
    require 'digest/md5'
    
    access_key_id = ENV['ALIYUN_ACCESS_KEY_ID']
    access_key_secret = ENV['ALIYUN_ACCESS_KEY_SECRET']
    bucket_name = 'operation-viodes'
    
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
  
  # OSS 直传签名接口
  def oss_signature
    require 'base64'
    require 'json'
    require 'openssl'
    
    endpoint = 'https://oss-cn-hangzhou.aliyuncs.com'
    access_key_id = ENV['ALIYUN_ACCESS_KEY_ID']
    access_key_secret = ENV['ALIYUN_ACCESS_KEY_SECRET']
    bucket_name = 'operation-viodes'
    
    raise "ALIYUN_ACCESS_KEY_ID 未配置" if access_key_id.blank?
    raise "ALIYUN_ACCESS_KEY_SECRET 未配置" if access_key_secret.blank?
    
    # 获取文件名（可选，前端传来的原始文件名）
    filename = params[:filename]
    
    # 生成文件名（UUID + 时间戳），直接放在 bucket 根目录
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
        ['content-length-range', 0, 500 * 1024 * 1024] # 限制文件大小最大500MB
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
    @q = OperationTask.ransack(params[:q])
    @operation_tasks = @q.result(distinct: true)
                         .includes(:account)
                         .order(created_at: :desc)
                         .page(params[:page])
                         .per(15)
    @themes = Theme.pluck(:name)
  end

  def show
  end

  def new
    @operation_task = OperationTask.new
    @themes = Theme.pluck(:name)
  end

  def create
    # 现在接收前端直传后的 OSS key，后端生成签名 URL
    if params[:oss_key].present?
      theme = operation_task_params[:theme]
      title = escape_quotes(operation_task_params[:title])
      description = escape_quotes(operation_task_params[:description])
      
      # 生成带签名的 URL（有效期7天）
      oss_url = generate_signed_url(params[:oss_key])

      platforms = %w[facebook twitter tiktok instagram]
      group_id = SecureRandom.uuid

      platforms.each do |platform|
        OperationTask.create(
          theme: theme,
          title: title,
          oss_url: oss_url,
          platform: platform,
          status: :pending,
          group_id: group_id
        )
      end
      OperationTask.create(
          theme: theme,
          title: description,
          description: title,
          oss_url: oss_url,
          platform: "youtube",
          status: :pending,
          group_id: group_id
        )
      redirect_to admin_operation_tasks_path, notice: '运营资源添加成功'
    else
      @operation_task = OperationTask.new(operation_task_params)
      render :new
    end
  end
  
  # 生成 OSS 签名 URL（有效期7天）
  def generate_signed_url(key)
    require 'base64'
    require 'openssl'
    
    access_key_id = ENV['ALIYUN_ACCESS_KEY_ID']
    access_key_secret = ENV['ALIYUN_ACCESS_KEY_SECRET']
    bucket_name = 'operation-viodes'
    
    verb = "GET"
    content_md5 = ""
    content_type = ""
    ts = (Time.now.to_i + 31536000)  # 1年有效期
    
    # 签名字符串中的 key 使用原始路径（不编码）
    cano_res = "/#{bucket_name}/#{key}"
    sign_string = "#{verb}\n#{content_md5}\n#{content_type}\n#{ts}\n#{cano_res}"
    
    # 生成签名
    signature = OpenSSL::HMAC.digest("sha1", access_key_secret, sign_string).to_s
    signature = Base64.strict_encode64(signature).strip
    signature = URI.encode_www_form_component(signature)
    
    # URL 中的 key 需要编码
    encoded_key = URI.encode_www_form_component(key)
    
    # 构建最终的签名 URL
    "https://#{bucket_name}.oss-cn-hangzhou.aliyuncs.com/#{encoded_key}?OSSAccessKeyId=#{access_key_id}&Expires=#{ts}&Signature=#{signature}"
  end

  def destroy
    unless @operation_task.pending?
      redirect_to admin_operation_tasks_path, alert: '仅 pending 状态的运营任务可被删除'
      return
    end

    @operation_task.destroy
    redirect_to admin_operation_tasks_path, notice: '运营任务已删除'
  end

  private

  # 对标题/简介中的双引号与反斜杠做反斜杠转义
  # 使用 block 形式确保反斜杠本身不被 gsub 语义误解
  def escape_quotes(value)
    return value if value.blank?
    value.to_s.gsub('\\') { '\\\\' }.gsub('"') { '\\"' }
  end

  def set_operation_task
    @operation_task = OperationTask.find(params[:id])
  end

  def operation_task_params
    params.require(:operation_task).permit(:theme, :title, :description, :oss_url, :platform, :status, :error_msg)
  end

  def upload_to_oss(file)
    require 'aliyun/oss'

    endpoint = 'https://oss-cn-hangzhou.aliyuncs.com'
    access_key_id = ENV['ALIYUN_ACCESS_KEY_ID']
    access_key_secret = ENV['ALIYUN_ACCESS_KEY_SECRET']
    bucket_name = 'operation-viodes'

    raise "ALIYUN_ACCESS_KEY_ID 未配置" if access_key_id.blank?
    raise "ALIYUN_ACCESS_KEY_SECRET 未配置" if access_key_secret.blank?

    client = Aliyun::OSS::Client.new(
      endpoint: endpoint,
      access_key_id: access_key_id,
      access_key_secret: access_key_secret
    )

    bucket = client.get_bucket(bucket_name)

    # 直接使用UUID作为文件名（保留扩展名），剔除原始文件名
    extension = File.extname(file.original_filename)
    base_name = "#{SecureRandom.uuid}#{extension}"
    
    bucket.put_object(base_name, file: file.tempfile.path)

    # 参考提供的代码生成签名URL（有效期7天）
    verb = "GET"
    content_md5 = ""
    content_type = ""
    ts = (Time.now.to_i + 31536000)  # 1年有效期
    
    # 文件名编码 - 签名字符串和URL中必须使用相同的编码方式
    encoded_filename = URI.encode_www_form_component(base_name)
    
    # 签名字符串中使用编码后的文件名
    cano_res = "/#{bucket_name}/#{encoded_filename}"
    sign_string = "#{verb}\n#{content_md5}\n#{content_type}\n#{ts}\n#{cano_res}"
    
    # 生成签名
    signature = OpenSSL::HMAC.digest("sha1", access_key_secret, sign_string).to_s
    signature = Base64.strict_encode64(signature).strip
    signature = URI.encode_www_form_component(signature)
    
    # 构建最终的签名URL - 使用相同的编码文件名
    signed_url = "https://#{bucket_name}.oss-cn-hangzhou.aliyuncs.com/#{encoded_filename}?OSSAccessKeyId=#{access_key_id}&Expires=#{ts}&Signature=#{signature}"
        
    return signed_url
  end

  # 手动生成OSS签名
  def generate_oss_signature(object_name, expires, access_key_id, access_key_secret, bucket_name)
    # 构建签名字符串 - 必须包含换行符，格式: GET\nContent-MD5\nContent-Type\nExpires\n/bucket/object
    string_to_sign = "GET\n\n\n#{expires}\n/#{bucket_name}/#{object_name}"
    
    # 打印签名字符串用于调试
    Rails.logger.info "签名字符串: #{string_to_sign.inspect}"
    
    # 使用HMAC-SHA1签名
    signature = OpenSSL::HMAC.digest('sha1', access_key_secret, string_to_sign)
    
    # Base64编码（使用标准encode64而非strict_encode64）
    Base64.encode64(signature).strip.gsub('+', '%2B').gsub('/', '%2F').gsub('=', '%3D')
  end
end