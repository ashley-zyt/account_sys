class Admin::TaskLogsController < Admin::BaseController
	def index
		@q = TaskLog.ransack(params[:q])
		task_associations = WorkMode.resource_modes.map { |m| { m.singular_association_name => [:account, :browser] } }
		@task_logs = @q.result(distinct: true)
		               .includes(*task_associations)
		               .order(run_at: :desc)
		               .page(params[:page])
		               .per(15)
		@work_types = Account.work_types.keys
	end

	def show
		@task_log = TaskLog.find(params[:id])
	end

	# 今日发布状况弹窗：统计各平台正常账号数、今日最终成功/失败，及最终失败账号列表
	def publish_status
		@summary = PublishDailySummary.compute(Date.today)
		render layout: false
	end
end
