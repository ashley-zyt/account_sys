class Admin::ConversationsController < Admin::BaseController
  before_action :set_conversation, only: [:show, :update_status]

  def index
    @q = Conversation.ransack(params[:q])
    @conversations = @q.result(distinct: true)
                       .includes(:kol, :kol_platform_account)
                       .order(created_at: :desc)
                       .page(params[:page])
                       .per(10)

    @platforms = Conversation.platforms.keys
    @statuses = Conversation.statuses.keys
    @kols = Kol.all
  end

  def show
    @messages = @conversation.conversation_messages.order(sent_at: :asc)
  end

  def update_status
    new_status = params[:status]

    valid_statuses = ["已合作", "已拒绝", "已关闭"]
    unless valid_statuses.include?(new_status)
      redirect_to admin_conversations_path, alert: "无效的状态值"
      return
    end

    if @conversation.update(status: new_status)
      redirect_to admin_conversations_path, notice: "会话状态已更新为「#{new_status}」"
    else
      redirect_to admin_conversations_path, alert: "更新失败：#{@conversation.errors.full_messages.join(', ')}"
    end
  rescue => e
    redirect_to admin_conversations_path, alert: "更新失败：#{e.message}"
  end

  private

  def set_conversation
    @conversation = Conversation.find(params[:id])
  end
end