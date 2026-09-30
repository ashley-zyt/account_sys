# KOL 触达「限制」统一管理：账号休眠、联系方式停用、每日尝试上限配置
class Admin::RestrictionsController < Admin::BaseController
  def index
    @max_contacts_per_day = KolAccountAllocator.max_contacts_per_day
    @sleeping_accounts = Account.active.where("kol_sleep_until > ?", Time.current).includes(:browser).order(:kol_sleep_until)
    @disabled_contacts = KolContact.where(status: :disabled).includes(:kol).order(updated_at: :desc)
  end

  # 解除账号休眠
  def unsleep_account
    account = Account.find(params[:account_id])
    account.update!(kol_sleep_until: nil)
    redirect_to admin_restrictions_path, notice: "已解除账号 #{account.account_name} 的休眠"
  end

  # 手动休眠账号（按 ID 或名称查找，指定时长或永久）
  def sleep_account
    key = params[:account_key].to_s.strip
    account = if key.match?(/\A\d+\z/)
      Account.find_by(id: key.to_i)
    else
      Account.find_by(account_name: key)
    end
    if account.nil?
      redirect_to admin_restrictions_path, alert: "找不到账号：#{key}"
      return
    end

    if params[:hours] == 'permanent'
      account.update!(kol_sleep_until: 100.years.from_now)
      redirect_to admin_restrictions_path, notice: "已永久休眠账号 #{account.account_name}"
    else
      hours = params[:hours].to_i
      hours = 24 if hours <= 0
      account.update!(kol_sleep_until: hours.hours.from_now)
      redirect_to admin_restrictions_path, notice: "已休眠账号 #{account.account_name} #{hours} 小时"
    end
  end

  # 恢复被停用的联系方式
  def restore_contact
    contact = KolContact.find(params[:contact_id])
    contact.update!(status: :active)
    redirect_to admin_restrictions_path, notice: "已恢复联系方式 ##{contact.id}（#{contact.platform}）"
  end

  # 手动停用联系方式（按 ID 或主页/昵称模糊查找）
  def disable_contact
    key = params[:contact_key].to_s.strip
    contact = if key.match?(/\A\d+\z/)
      KolContact.find_by(id: key.to_i)
    else
      KolContact.where("url LIKE :k OR nickname LIKE :k", k: "%#{key}%").order(:id).first
    end
    if contact.nil?
      redirect_to admin_restrictions_path, alert: "找不到联系方式：#{key}"
      return
    end

    contact.update!(status: :disabled)
    redirect_to admin_restrictions_path, notice: "已停用联系方式 ##{contact.id}（#{contact.platform}）"
  end

  # 更新配置（每日尝试上限）
  def update_settings
    max_per_day = params[:max_contacts_per_day].to_i
    if max_per_day <= 0
      redirect_to admin_restrictions_path, alert: "每日尝试上限必须大于 0"
      return
    end

    update_yml('max_contacts_per_day', max_per_day)
    KolAccountAllocator.reload_settings!
    redirect_to admin_restrictions_path, notice: "已更新每日尝试上限为 #{max_per_day} 次"
  end

  private

  # 更新 config/kol_scheduler.yml 的单个键值（正则替换，保留注释与其它配置）
  def update_yml(key, value)
    require 'yaml'
    path = KolAccountAllocator::CONFIG_PATH
    content = File.read(path)
    if content.match?(/^#{Regexp.escape(key)}:\s*.*$/)
      content = content.sub(/^#{Regexp.escape(key)}:\s*.*$/, "#{key}: #{value}")
    else
      content = content.rstrip + "\n#{key}: #{value}\n"
    end
    File.write(path, content)
  end
end
