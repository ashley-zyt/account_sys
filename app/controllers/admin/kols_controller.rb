class Admin::KolsController < Admin::BaseController
  before_action :set_kol, only: [
    :show, :edit, :update, :destroy,
    :activate, :deactivate, :contact_now, :take_over,
    :mark_outcome, :mark_auto_reply, :add_message
  ]
  before_action :load_dictionaries, only: [:index, :new, :create, :edit, :update, :show]

  def index
    @q = Kol.ransack(params[:q])
    @kols = @q.result(distinct: true)
              .includes(:current_account, :domain, :language)
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
    @suggested_variables = suggested_variables_for(@kol)
  end

  def create
    @kol = Kol.new(kol_params)
    apply_follower_tier(@kol, params.dig(:kol, :follower_tier))
    apply_domain(@kol, params.dig(:kol))
    apply_language(@kol, params.dig(:kol))

    if @kol.save
      sync_variables(@kol, params[:kol_variables])
      redirect_to admin_kol_path(@kol), notice: "KOL 已成功录入"
    else
      @kol.kol_contacts.build if @kol.kol_contacts.empty?
      @suggested_variables = suggested_variables_for(@kol)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @suggested_variables = suggested_variables_for(@kol)
  end

  def update
    apply_follower_tier(@kol, params.dig(:kol, :follower_tier))
    apply_domain(@kol, params.dig(:kol))
    apply_language(@kol, params.dig(:kol))

    if @kol.update(kol_params)
      sync_variables(@kol, params[:kol_variables])
      redirect_to admin_kol_path(@kol), notice: "KOL 信息已更新"
    else
      @suggested_variables = suggested_variables_for(@kol)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @kol.destroy
    redirect_to admin_kols_path, notice: "KOL 已删除"
  end

  def activate
    @kol.enqueue!
    redirect_to admin_kol_path(@kol), notice: "已加入自动化触达队列"
  end

  def deactivate
    @kol.dequeue!
    redirect_to admin_kol_path(@kol), notice: "已移出触达队列，转入储备池"
  end

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

  def take_over
    @kol.update!(status: :negotiating, next_action_at: nil)
    redirect_to admin_kol_path(@kol), notice: "已转入人工跟进"
  end

  def mark_outcome
    outcome = params[:outcome].to_s
    status = outcome == "cooperating" ? :cooperating : :failed
    @kol.update!(status: status, next_action_at: nil)
    redirect_to admin_kol_path(@kol), notice: "已更新合作结果"
  end

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

  def load_dictionaries
    @domains = Domain.order(:name)
    @languages = Language.order(:id)
    @message_variables = MessageVariable.order(:id)
  end

  def kol_params
    params.require(:kol).permit(
      :name, :country, :owner, :notes, :status,
      kol_contacts_attributes: [
        :id, :platform, :nickname, :url, :priority, :messaging_enabled, :_destroy
      ]
    )
  end

  # 粉丝量级：表单传 "min,max"（max 可为空），转为 follower_min / follower_max
  def apply_follower_tier(kol, tier_str)
    return if tier_str.blank?
    min_s, max_s = tier_str.to_s.split(",", 2)
    kol.follower_min = min_s.present? ? min_s.to_i : nil
    kol.follower_max = max_s.present? ? max_s.to_i : nil
  end

  # 领域：combobox 提交名称，同名去重、不存在则创建
  def apply_domain(kol, attrs)
    return if attrs.nil?
    name = attrs[:domain_name].to_s.strip
    kol.domain_id = name.present? ? Domain.find_or_create_by_name(name)&.id : nil
  end

  # 语言：combobox 提交名称，同名去重、不存在则创建
  def apply_language(kol, attrs)
    return if attrs.nil?
    name = attrs[:language_name].to_s.strip
    kol.language_id = name.present? ? Language.find_or_create_by_name(name)&.id : nil
  end

  # 同步 KOL 变量值（键值对）；有填写值则清除"待补全"标记
  def sync_variables(kol, variables_hash)
    kol.sync_variables!(variables_hash)
    if variables_hash.present? && variables_hash.values.any? { |v| v.to_s.strip.present? }
      kol.update!(variables_incomplete: false)
    end
  end

  def suggested_variables_for(kol)
    platforms = kol.kol_contacts.map(&:platform).compact
    MessageTemplate.suggested_variables(
      scenario: :first_contact,
      platforms: platforms,
      domain_id: kol.domain_id
    )
  end
end
