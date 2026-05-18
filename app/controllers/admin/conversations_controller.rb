class Admin::ConversationsController < Admin::BaseController
  before_action :set_conversation, only: [:show]

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

  private

  def set_conversation
    @conversation = Conversation.find(params[:id])
  end
end