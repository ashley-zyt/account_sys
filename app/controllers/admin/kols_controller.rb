class Admin::KolsController < Admin::BaseController
  before_action :set_kol, only: [
    :show, :edit, :update, :destroy,
    :activate, :deactivate, :contact_now, :take_over,
    :mark_outcome, :mark_auto_reply, :add_message, :conversation,
    :reply_message, :quick_status
  ]
  before_action :load_dictionaries, only: [:index, :new, :create, :edit, :update, :show]

  def index
    @q = Kol.ransack(params[:q])
    @kols = @q.result(distinct: true)
              .includes(:current_account, :domain, :language, :kol_contacts)
              .order(created_at: :desc)
              .page(params[:page])
              .per(15)
    @status_counts = {}
    Kol.statuses.each_key { |key| @status_counts[key] = Kol.where(status: key).count }
    @variables_incomplete_count = Kol.where(variables_incomplete: true).count
  end

  def show
    @contacts = @kol.kol_contacts.order(priority: :asc, id: :asc)
    @messages = @kol.kol_messages
                    .includes(:account, :kol_contact)
                    .order(Arel.sql("occurred_at IS NULL ASC, occurred_at ASC, id ASC"))
    @accounts = Account.active.order(:platform, :account_name)
    @manual_templates = manual_templates_for(@kol)
  end

  # 列表页抽屉里的跨渠道会话流（无布局，供 fetch 注入）
  def conversation
    @messages = @kol.kol_messages
                    .includes(:account, :kol_contact)
                    .order(Arel.sql("occurred_at IS NULL ASC, occurred_at ASC, id ASC"))
    @contacts = @kol.kol_contacts.order(priority: :asc, id: :asc)

    # 默认选中：已回复的联系方式 > 当前正在联系 > 最近有消息的渠道 > 第一个渠道
    replied_contact = @kol.kol_contacts.where(status: KolContact.statuses[:replied]).order(id: :desc).first
    latest_contact_id = @messages
      .reject { |m| m.kol_contact_id.nil? }
      .max_by { |m| m.occurred_at || m.created_at }
      &.kol_contact_id
    @active_contact_id = replied_contact&.id || @kol.current_contact_id || latest_contact_id || @contacts.first&.id

    # 回复用：全部模板（渲染后的内容 + 缺失变量）+ 回复账号（取「已回复」联系方式的账号）
    @reply_templates = MessageTemplate.order(:id).map do |t|
      {
        id: t.id,
        label: "#{t.scenario_label} · #{t.name}",
        content: t.render_for(@kol).to_s,
        missing: @kol.missing_variables(t.required_variable_keys)
      }
    end
    @reply_contact = replied_contact || @kol.current_contact
    @reply_account = @reply_contact&.last_outgoing_account || @kol.current_account
    render layout: false
  end

  def new
    @kol = Kol.new(status: :pending)
    @kol.kol_contacts.build
    @suggested_variables = suggested_variables_for(@kol)
    prepare_variable_data(@kol)
  end

  def create
    @kol = Kol.new(kol_params)
    apply_follower_tier(@kol, params.dig(:kol, :follower_tier))
    apply_domain(@kol, params.dig(:kol))
    apply_language(@kol, params.dig(:kol))

    if @kol.save
      downgraded = finalize_kol(@kol, params[:kol_variables])
      notice = downgraded ? "KOL 已保存，因缺少联系方式或必要变量，已自动转为「未开始」" : "KOL 已成功录入"
      redirect_to admin_kol_path(@kol), notice: notice
    else
      @kol.kol_contacts.build if @kol.kol_contacts.empty?
      @suggested_variables = suggested_variables_for(@kol)
      prepare_variable_data(@kol)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @suggested_variables = suggested_variables_for(@kol)
    prepare_variable_data(@kol)
  end

  def update
    apply_follower_tier(@kol, params.dig(:kol, :follower_tier))
    apply_domain(@kol, params.dig(:kol))
    apply_language(@kol, params.dig(:kol))

    if @kol.update(kol_params)
      downgraded = finalize_kol(@kol, params[:kol_variables])
      notice = downgraded ? "KOL 已保存，因缺少联系方式或必要变量，已自动转为「未开始」" : "KOL 信息已更新"
      redirect_to admin_kol_path(@kol), notice: notice
    else
      @suggested_variables = suggested_variables_for(@kol)
      prepare_variable_data(@kol)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @kol.destroy
    redirect_to admin_kols_path, notice: "KOL 已删除"
  end

  # 加入自动化触达队列（Reserved → Pending）
  def activate
    if @kol.enqueue!
      redirect_to admin_kol_path(@kol), notice: "已转为待联系"
    else
      redirect_to admin_kol_path(@kol), alert: "该 KOL 缺少可触达的联系方式或必要变量，无法转入待联系"
    end
  end

  # 移出队列（Pending → Reserved）
  def deactivate
    @kol.dequeue!
    redirect_to admin_kol_path(@kol), notice: "已转为未开始"
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
    template_id = params[:template_id].to_s.strip

    # 内容为空时，若选择了模板则用模板渲染结果填充
    if content.blank? && template_id.present?
      template = MessageTemplate.find_by(id: template_id)
      content = template&.render_for(@kol).to_s.strip
    end

    if content.blank?
      redirect_to admin_kol_path(@kol), alert: "消息内容不能为空"
      return
    end

    # 若内容里仍残留未替换的 ${变量} 占位符，提醒补齐变量
    if content.include?("${")
      redirect_to admin_kol_path(@kol), alert: "消息内容中仍包含未填写的变量（${...}），请先补全后再发送"
      return
    end

    result = KolScheduler.manual_send(@kol, contact: contact, account: account, content: content)
    if result[:ok]
      redirect_to admin_kol_path(@kol), notice: "消息已发送"
    else
      redirect_to admin_kol_path(@kol), alert: result[:error]
    end
  end

  # 会话抽屉快捷回复：账号固定用「对方回复来的那个联系方式的账号」，防止串号
  def reply_message
    content = params[:content].to_s.strip
    template_id = params[:template_id].to_s.strip

    # 优先回复「已回复」的联系方式；其次用前端传入的；最后退回当前联系方式
    contact = @kol.kol_contacts.find_by(id: params[:kol_contact_id])
    contact ||= @kol.kol_contacts.where(status: KolContact.statuses[:replied]).order(id: :desc).first
    contact ||= @kol.current_contact

    # 优先用输入框内容；输入框为空时才用模板渲染
    if content.blank? && template_id.present?
      template = MessageTemplate.find_by(id: template_id)
      content = template&.render_for(@kol).to_s.strip
    end

    return render json: { success: false, message: "回复内容不能为空" } if content.blank?
    return render json: { success: false, message: "缺少联系渠道" } if contact.nil?

    account = contact.last_outgoing_account || @kol.current_account
    return render json: { success: false, message: "该 KOL 缺少可回复的内部账号" } if account.nil?

    result = KolScheduler.manual_send(@kol, contact: contact, account: account, content: content)
    if result[:ok]
      render json: { success: true, message: "回复已发送" }
    else
      render json: { success: false, message: result[:error] }
    end
  end

  # 会话抽屉快捷改状态 + 追加备注（status / note 至少一项）
  def quick_status
    status = params[:status].to_s
    note = params[:note].to_s.strip

    updates = {}
    if status.present?
      return render json: { success: false, message: "无效的状态" } unless Kol.statuses.key?(status)
      updates[:status] = status
      updates[:next_action_at] = nil
    end
    if note.present?
      existing = @kol.notes.to_s.strip
      updates[:notes] = existing.present? ? "#{existing}\n#{note}" : note
    end

    return render json: { success: false, message: "没有可更新的内容" } if updates.empty?

    @kol.update!(updates)
    render json: { success: true, message: "已更新" }
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
    ok = false
    if incoming
      incoming.update!(is_auto_reply: true)
      # 该回复是机器人自动回复：联系方式恢复监测，KOL 恢复等待
      incoming.kol_contact&.update!(status: :contacting, monitor_until: 30.days.from_now)
      @kol.update!(status: :contacting, next_action_at: nil)
      ok = true
    end

    respond_to do |format|
      format.html do
        if ok
          redirect_to admin_kol_path(@kol), notice: "已标记为自动回复，恢复等待倒计时"
        else
          redirect_to admin_kol_path(@kol), alert: "未找到可标记的回复"
        end
      end
      format.json do
        if ok
          render json: { success: true, message: "已标记为自动回复" }
        else
          render json: { success: false, message: "未找到可标记的回复" }
        end
      end
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

  # 同步 KOL 变量值，并据实重算「待补全变量」标记；
  # 若 KOL 处于「待联系」但尚不具备触达条件（无渠道 / 缺变量），自动回落到「未开始」。
  # 返回是否发生了回落。
  def finalize_kol(kol, variables_hash)
    kol.sync_variables!(variables_hash)

    incomplete = kol.missing_entry_variables.any?
    has_contacts = kol.has_outreachable_contacts?

    downgraded = false
    if kol.status.to_s == "pending" && (!has_contacts || incomplete)
      kol.update!(status: :reserved)
      downgraded = true
    end

    kol.update!(variables_incomplete: incomplete)
    downgraded
  end

  def suggested_variables_for(kol)
    platforms = kol.kol_contacts.map(&:platform).compact
    MessageTemplate.suggested_variables(
      scenario: :first_contact,
      platforms: platforms,
      domain_id: kol.domain_id
    )
  end

  # 人工发送消息可选模板（渲染后的内容 + 缺失变量，供前端套用与提醒）
  def manual_templates_for(kol)
    MessageTemplate.order(:id).map do |t|
      {
        id: t.id,
        label: "#{t.scenario_label} · #{t.name}",
        content: t.render_for(kol).to_s,
        missing: kol.missing_variables(t.required_variable_keys)
      }
    end
  end

  # 为前端「按领域/平台动态匹配变量」准备数据
  def prepare_variable_data(kol)
    @template_var_data = MessageTemplate.where(scenario: :first_contact)
      .includes(:domain, :message_variables)
      .map do |t|
        {
          domain_name: t.domain&.name,
          platform: t.platform,
          variables: t.message_variables.map(&:identifier)
        }
      end
    @all_variables_data = @message_variables.map do |v|
      {
        identifier: v.identifier,
        name: v.name,
        description: v.description,
        value: kol.variable_value(v.identifier)
      }
    end
  end
end
