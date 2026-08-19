class Admin::KolsController < Admin::BaseController
  before_action :set_kol, only: [
    :show, :edit, :update, :destroy,
    :activate, :deactivate, :contact_now, :take_over,
    :mark_outcome, :mark_auto_reply, :add_message
  ]

  def index
    @q = Kol.ransack(params[:q])
    @kols = @q.result(distinct: true)
              .includes(:current_account)
              .order(created_at: :desc)
              .page(params[:page])
              .per(15)
  end

  def show
    @contacts = @kol.kol_contacts.order(priority: :asc, id: :asc)
    @messages = @kol.kol_messages
                    .includes(:account, :kol_contact)
                    .order(Arel.sql("occurred_at IS NULL ASC, occurred_at ASC, id ASC"))
    @accounts = Account.active.order(:platform, :account_name)
  end

  def new
    @kol = Kol.new
    @kol.kol_contacts.build
  end

  def create
    @kol = Kol.new(kol_params)
    if @kol.save
      redirect_to admin_kol_path(@kol), notice: "KOL 已成功录入"
    else
      @kol.kol_contacts.build if @kol.kol_contacts.empty?
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @kol.update(kol_params)
      redirect_to admin_kol_path(@kol), notice: "KOL 信息已更新"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @kol.destroy
    redirect_to admin_kols_path, notice: "KOL 已删除"
  end

  # 加入自动化触达队列（Reserved → Pending）
  def activate
    @kol.enqueue!
    redirect_to admin_kol_path(@kol), notice: "已加入自动化触达队列"
  end

  # 移出队列（Pending → Reserved）
  def deactivate
    @kol.dequeue!
    redirect_to admin_kol_path(@kol), notice: "已移出触达队列，转入储备池"
  end

  # 立即联系（人工触发，最高优先级）
  def contact_now
    contact = KolContact.find_by(id: params[:kol_contact_id])
    account = Account.find_by(id: params[:account_id])
    result = KolScheduler.manual_contact(@kol, contact: contact, account: account, content: params[:content])
    if result[:ok]
      redirect_to admin_kol_path(@kol), notice: "已立即联系该 KOL"
    else
      redirect_to admin_kol_path(@kol), alert: result[:error]
    end
  end

  # 人工打字发送消息
  def add_message
    contact = KolContact.find_by(id: params[:kol_contact_id])
    account = Account.find_by(id: params[:account_id])
    content = params[:content].to_s.strip
    if content.blank?
      redirect_to admin_kol_path(@kol), alert: "消息内容不能为空"
      return
    end
    result = KolScheduler.manual_send(@kol, contact: contact, account: account, content: content)
    if result[:ok]
      redirect_to admin_kol_path(@kol), notice: "消息已发送"
    else
      redirect_to admin_kol_path(@kol), alert: result[:error]
    end
  end

  # 人工接管（Replied_Unprocessed → Negotiating）
  def take_over
    @kol.update!(status: :negotiating, next_action_at: nil)
    redirect_to admin_kol_path(@kol), notice: "已转入人工跟进"
  end

  # 标记最终结果（已合作 / 未能合作）
  def mark_outcome
    outcome = params[:outcome].to_s
    status = outcome == "cooperating" ? :cooperating : :failed
    @kol.update!(status: status, next_action_at: nil)
    redirect_to admin_kol_path(@kol), notice: "已更新合作结果"
  end

  # 标记对方回复为自动回复（假回复），恢复等待倒计时
  def mark_auto_reply
    incoming = @kol.latest_incoming_reply
    if incoming
      incoming.update!(is_auto_reply: true)
      outgoing = @kol.latest_outgoing_message
      @kol.update!(status: :contacting, next_action_at: outgoing&.wait_until || Time.current)
      redirect_to admin_kol_path(@kol), notice: "已标记为自动回复，恢复等待倒计时"
    else
      redirect_to admin_kol_path(@kol), alert: "未找到可标记的回复"
    end
  end

  private

  def set_kol
    @kol = Kol.find(params[:id])
  end

  def kol_params
    params.require(:kol).permit(
      :name, :category, :follower_tier, :country, :language, :owner, :notes, :status,
      kol_contacts_attributes: [
        :id, :platform, :nickname, :url, :priority, :messaging_enabled, :status, :_destroy
      ]
    )
  end
end
