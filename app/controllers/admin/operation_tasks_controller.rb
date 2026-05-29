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

		if @operation_task.save
			redirect_to admin_operation_tasks_path, notice: '运营资源添加成功'
		else
			render :new
		end
	end

	def get_upload_params
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
		end

		bucket = client.get_bucket(bucket_name)

		file_name = params[:file_name]
		raise "缺少文件名" if file_name.blank?

		expire_seconds = 3600
		url = bucket.object_url(file_name, Time.now + expire_seconds)

		render json: {
			oss_url: url.split('?').first,
			upload_url: url,
			file_name: file_name
		}
	end

	private

	def set_operation_task
		@operation_task = OperationTask.find(params[:id])
	end

	def operation_task_params
		params.require(:operation_task).permit(:theme, :title, :oss_url, :platform, :status, :error_msg)
	end
end