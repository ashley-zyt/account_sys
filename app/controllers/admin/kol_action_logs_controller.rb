class Admin::KolActionLogsController < Admin::BaseController
  # KOL 触达动作日志：记录「发私信」「检查回复」每次动作的执行流水
  # （与 KolMessage 的「消息」维度互补，这里看的是「动作」维度）
  def index
    @q = KolActionLog.ransack(params[:q])
    @logs = @q.result(distinct: true)
               .includes(:kol, :kol_contact, :account)
               .order(created_at: :desc)
               .page(params[:page])
               .per(20)
  end
end
