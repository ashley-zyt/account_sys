class Admin::OperationLogsController < Admin::BaseController
  def index
    @q = OperationLog.ransack(params[:q])
    @operation_logs = @q.result(distinct: true)
                       .order(created_at: :desc)
                       .page(params[:page])
                       .per(15)

    @admins = Admin.pluck(:id, :username)
  end
end
