class Admin::KolsController < Admin::BaseController
  before_action :set_kol, only: [:show, :edit, :update, :initiate_contact, :start_conversation]

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

  def initiate_contact
    @templates = MessageTemplate.all
    @platform_accounts = @kol.kol_platform_accounts
    render layout: false
  end

  def start_conversation
    Rails.logger.info "[start_conversation] 开始创建会话"
    Rails.logger.info "[start_conversation] params: #{params.inspect}"

    template = MessageTemplate.find(params[:template_id])
    Rails.logger.info "[start_conversation] template found: #{template.id}"

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

    contacted_account_ids = @kol.conversations.pluck(:account_id).uniq
    Rails.logger.info "[start_conversation] contacted_account_ids: #{contacted_account_ids}"

    if contacted_account_ids.present?
      uncontacted_accounts = accounts.where.not(id: contacted_account_ids)
    else
      uncontacted_accounts = accounts
    end
    Rails.logger.info "[start_conversation] uncontacted_accounts count: #{uncontacted_accounts.count}"

    if uncontacted_accounts.any?
      account = uncontacted_accounts.order('last_used_at ASC NULLS FIRST').first
    else
      account = accounts.order('last_used_at ASC NULLS FIRST').first
    end
    Rails.logger.info "[start_conversation] selected account: #{account.id}, #{account.account_name}"

    conversation = Conversation.new(
      kol: @kol,
      kol_platform_account: kol_platform_account,
      account: account,
      platform: platform_value,
      status: 0,
      latest_message: template.content.truncate(100)
    )
    Rails.logger.info "[start_conversation] conversation prepared, about to save"

    if conversation.save
      Rails.logger.info "[start_conversation] conversation saved successfully: #{conversation.id}"
      account.mark_as_assigned!
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