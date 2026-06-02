class Admin::OperationTasksController < Admin::BaseController
  before_action :set_operation_task, only: [:show]

  def index
    @q = OperationTask.ransack(params[:q])
    @operation_tasks = @q.result(distinct: true)
                         .includes(:account)
                         .order(created_at: :desc)
                         .page(params[:page])
                         .per(10)
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

    encoded_filename = URI.encode(file.original_filename, /[^a-zA-Z0-9\.\-\_]/)
    file_name = "#{SecureRandom.uuid}_#{encoded_filename}"

    bucket.put_object(file_name, file: file.tempfile.path)

    # 手动生成带签名的URL（有效期1年）
    expires = (Time.now + 365 * 24 * 3600).to_i
    
    # 签名字符串中使用原始文件名（不编码）
    signature = generate_oss_signature(file_name, expires, access_key_id, access_key_secret, bucket_name)
    
    # URL中使用编码后的文件名
    encoded_file_name = URI.encode(file_name, /[^a-zA-Z0-9\.\-\_\/]/)
    signed_url = "https://#{bucket_name}.oss-cn-hangzhou.aliyuncs.com/#{encoded_file_name}?OSSAccessKeyId=#{access_key_id}&Expires=#{expires}&Signature=#{URI.encode(signature)}"
    
    # 打印日志验证签名URL
    Rails.logger.info "========== OSS上传调试 =========="
    Rails.logger.info "原始文件名: #{file.original_filename}"
    Rails.logger.info "OSS对象名: #{file_name}"
    Rails.logger.info "生成的签名URL: #{signed_url}"
    Rails.logger.info "URL包含Signature: #{signed_url.include?('Signature')}"
    Rails.logger.info "URL包含Expires: #{signed_url.include?('Expires')}"
    Rails.logger.info "=================================="
    
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