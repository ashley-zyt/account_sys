class Admin::OperationTasksController < Admin::BaseController
  before_action :set_operation_task, only: [:show]

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
    if params[:video_file].present?
      oss_url = upload_to_oss(params[:video_file])
      theme = operation_task_params[:theme]
      title = operation_task_params[:title]

      platforms = %w[facebook twitter tiktok instagram]
      group_id = SecureRandom.uuid

      description = operation_task_params[:description]

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

  private

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
    ts = (Time.now.to_i + 604800)  # 7天有效期
    
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