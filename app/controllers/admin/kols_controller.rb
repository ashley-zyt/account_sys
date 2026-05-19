class Admin::KolsController < Admin::BaseController
  before_action :set_kol, only: [:show, :edit, :update, :destroy, :initiate_contact, :start_conversation]

  def index
    @q = Kol.ransack(params[:q])
    @kols = @q.result(distinct: true)
             .order(created_at: :desc)
             .page(params[:page])
             .per(10)

    @categories = Kol.pluck(:category).compact.uniq
    @locations = Kol.pluck(:location).compact.uniq
  end

  def show
    @platform_accounts = @kol.kol_platform_accounts.includes(:conversations)
    @conversations = @kol.conversations.includes(:kol_platform_account).order(created_at: :desc)

    @accounts = Account.all
    @templates = MessageTemplate.all
  end

  def new
    @kol = Kol.new
    @kol.kol_platform_accounts.build
  end

  def create
    @kol = Kol.new(kol_params)
    if @kol.save
      redirect_to admin_kol_path(@kol), notice: "KOL已成功创建"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @kol.update(kol_params)
      redirect_to admin_kol_path(@kol), notice: "KOL信息已更新"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    kol_name = @kol.kol_name
    conversation_count = @kol.conversations.count
    message_count = @kol.conversations.joins(:conversation_messages).count

    if @kol.destroy
      redirect_to admin_kols_path, notice: "已成功删除KOL「#{kol_name}」，同时清除了 #{conversation_count} 个会话和 #{message_count} 条消息"
    else
      redirect_to admin_kols_path, alert: "删除失败：#{@kol.errors.full_messages.join(', ')}"
    end
  rescue => e
    redirect_to admin_kols_path, alert: "删除失败：#{e.message}"
  end

  def initiate_contact
    @templates = MessageTemplate.all
    @platform_accounts = @kol.kol_platform_accounts
    render layout: false
  end

  def start_conversation
    Rails.logger.info "[start_conversation] 开始创建会话"
    Rails.logger.info "[start_conversation] params: #{params.inspect}"

    kol_platform_account = KolPlatformAccount.find(params[:kol_platform_account_id])
    Rails.logger.info "[start_conversation] kol_platform_account found: #{kol_platform_account.id}, platform: #{kol_platform_account.platform}"

    platform = kol_platform_account.platform
    platform_value = platform.is_a?(Integer) ? platform : Account.platforms[platform]
    Rails.logger.info "[start_conversation] platform_value: #{platform_value}"

    accounts = Account.where(status: "正常").where(platform: platform_value)
    Rails.logger.info "[start_conversation] accounts count: #{accounts.count}"

    if accounts.empty?
      Rails.logger.error "[start_conversation] 该平台没有可用的运营账号"
      redirect_to admin_kol_path(@kol), alert: "该平台没有可用的运营账号"
      return
    end

    account = select_least_used_account(accounts)
    Rails.logger.info "[start_conversation] selected account: #{account.id}, #{account.account_name}"

    custom_message = params[:custom_message]&.strip
    template_id = params[:template_id]

    if custom_message.present?
      message_content = custom_message
      Rails.logger.info "[start_conversation] 使用自定义消息"
    elsif template_id.present?
      template = MessageTemplate.find(template_id)
      message_content = template.content
      Rails.logger.info "[start_conversation] 使用模板消息: #{template.id}"
    else
      Rails.logger.error "[start_conversation] 没有提供消息内容"
      redirect_to admin_kol_path(@kol), alert: "请选择消息模板或输入自定义消息"
      return
    end

    conversation = Conversation.new(
      kol: @kol,
      kol_platform_account: kol_platform_account,
      account: account,
      platform: platform_value,
      status: 0,
      latest_message: message_content.truncate(100)
    )
    Rails.logger.info "[start_conversation] conversation prepared, about to save"

    if conversation.save
      Rails.logger.info "[start_conversation] conversation saved successfully: #{conversation.id}"
      redirect_to admin_kol_path(@kol), notice: "已成功发起会话"
    else
      Rails.logger.error "[start_conversation] conversation save failed: #{conversation.errors.full_messages}"
      redirect_to admin_kol_path(@kol), alert: "创建会话失败：#{conversation.errors.full_messages.join(', ')}"
    end
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "[start_conversation] RecordNotFound: #{e.message}"
    redirect_to admin_kol_path(@kol), alert: "创建会话失败：#{e.message}"
  rescue => e
    Rails.logger.error "[start_conversation] Error: #{e.class}, #{e.message}"
    redirect_to admin_kol_path(@kol), alert: "创建会话失败：#{e.message}"
  end

  private

  def select_least_used_account(accounts)
    account_ids = accounts.pluck(:id)

    conversation_counts = Conversation.where(account_id: account_ids)
      .group(:account_id)
      .count

    accounts_array = accounts.map do |account|
      {
        account: account,
        conversation_count: conversation_counts[account.id] || 0
      }
    end

    accounts_array.sort_by! { |item| [item[:conversation_count], item[:account].id] }

    accounts_array.first[:account]
  end

  def set_kol
    @kol = Kol.find(params[:id])
  end

  def kol_params
    params.require(:kol).permit(
      :kol_name,
      :nick_name,
      :location,
      :category,
      :notes,
      kol_platform_accounts_attributes: [:id, :platform, :nick_name, :profile_url, :follower_count, :_destroy]
    )
  end
end