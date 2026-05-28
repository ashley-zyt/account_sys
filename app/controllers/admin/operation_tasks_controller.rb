class Admin::OperationTasksController < Admin::BaseController
	before_action :set_operation_task, only: [:show]

	def index
		@q = OperationTask.ransack(params[:q])
		@operation_tasks = @q.result(distinct: true)
		                   .includes(:account)
		                   .order(created_at: :desc)
		                   .page(params[:page])
		                   .per(10)
	end

	def show
	end

	def new
		@operation_task = OperationTask.new
	end

	def create
		@operation_task = OperationTask.new(operation_task_params)

		# 上传视频到 OSS
		if params[:video_file].present?
			oss_url = upload_to_oss(params[:video_file])
			@operation_task.oss_url = oss_url
		end

		if @operation_task.save
			redirect_to admin_operation_tasks_path, notice: '运营资源添加成功'
		else
			render :new
		end
	end

	private

	def set_operation_task
		@operation_task = OperationTask.find(params[:id])
	end

	def operation_task_params
		params.require(:operation_task).permit(:theme, :title)
	end

	def upload_to_oss(file)
		require 'aliyun/oss'
		
		endpoint = 'https://oss-cn-hangzhou.aliyuncs.com'
		access_key_id = ENV['ALIYUN_ACCESS_KEY_ID']
		access_key_secret = ENV['ALIYUN_ACCESS_KEY_SECRET']
		bucket_name = 'operation-viodes'

		# 验证配置
		raise "ALIYUN_ACCESS_KEY_ID 未配置" if access_key_id.blank?
		raise "ALIYUN_ACCESS_KEY_SECRET 未配置" if access_key_secret.blank?

		client = Aliyun::OSS::Client.new(
			endpoint: endpoint,
			access_key_id: access_key_id,
			access_key_secret: access_key_secret
		)

		bucket = client.get_bucket(bucket_name)

		# 生成唯一文件名（处理中文文件名）
		encoded_filename = URI.encode(file.original_filename, /[^a-zA-Z0-9\.\-\_]/)
		file_name = "#{SecureRandom.uuid}_#{encoded_filename}"
		
		# 上传文件 - 使用 put_object 方法的正确格式
		bucket.put_object(file_name, file: file.tempfile.path)

		# 生成公共访问 URL（如果 bucket 是公共读）
		"https://#{bucket_name}.oss-cn-hangzhou.aliyuncs.com/#{file_name}"
	end
end