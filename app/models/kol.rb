# == Schema Information
#
# Table name: kols
#
#  id                 :bigint           not null, primary key
#  category           :string(255)
#  country            :string(255)
#  current_account_id :bigint
#  current_contact_id :bigint
#  follower_tier      :string(255)
#  language           :string(255)      not null
#  last_contacted_at  :datetime
#  name               :string(255)      not null
#  next_action_at     :datetime
#  notes              :text(65535)
#  owner              :string(255)      not null
#  status             :integer          default("reserved")
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
class Kol < ApplicationRecord
  has_many :kol_contacts, dependent: :destroy
  has_many :kol_messages, dependent: :destroy

  belongs_to :current_contact, class_name: "KolContact", optional: true
  belongs_to :current_account, class_name: "Account", optional: true

  accepts_nested_attributes_for :kol_contacts, allow_destroy: true, reject_if: proc { |attrs| attrs["platform"].blank? }

  # 第一层：KOL 业务生命周期状态
  enum status: {
    reserved: 0,              # 储备中（隔离于自动化队列之外）
    pending: 1,               # 待触达（等待后台队列分配账号）
    contacting: 2,            # 触达中（已发送，等待回复）
    replied_unprocessed: 3,   # 已回复_待处理（暂停自动化，等待人工审阅）
    negotiating: 4,           # 人工跟进中
    cooperating: 5,           # 已合作
    failed: 6,                # 未能合作
    unresponsive: 7           # 无响应（所有渠道均无回复）
  }

  validates :name, presence: true
  validates :language, presence: true
  validates :owner, presence: true

  validate :check_duplicate, on: :create

  # 可发信且未失效的联系渠道，按优先级升序（优先级数值越小越靠前）
  def active_contacts
    kol_contacts.where(status: :active)
                .where(messaging_enabled: true)
                .order(priority: :asc, id: :asc)
  end

  # 触发自动化触达（进入 pending 队列）
  def enqueue!
    update!(status: :pending, next_action_at: nil)
  end

  # 从队列中撤下（回到储备池）
  def dequeue!
    update!(status: :reserved, next_action_at: nil)
  end

  # 最近一条对方回复
  def latest_incoming_reply
    kol_messages.where(direction: :incoming, status: :replied).order(id: :desc).first
  end

  # 最近一条我方发出的消息
  def latest_outgoing_message
    kol_messages.where(direction: :outgoing).order(id: :desc).first
  end

  scope :pending_queue, -> { where(status: :pending).order(created_at: :asc) }

  # 全局查重：基于精确用户名 / 平台主页链接 / 邮箱 判断是否已存在
  def self.find_duplicate(name:, contact_urls: [], contact_emails: [], exclude_id: nil)
    urls = Array(contact_urls).map(&:to_s).map(&:strip).reject(&:blank?).uniq
    emails = Array(contact_emails).map(&:to_s).map(&:strip).reject(&:blank?).uniq
    kol_ids = []

    if name.present?
      scope = Kol.where(name: name)
      scope = scope.where.not(id: exclude_id) if exclude_id.present?
      kol_ids.concat(scope.pluck(:id))
    end

    kol_ids.concat(KolContact.where("url IN (?)", urls).pluck(:kol_id)) if urls.any?

    if emails.any?
      kol_ids.concat(
        KolContact.where(platform: KolContact.platforms[:email])
          .where("url IN (?) OR nickname IN (?)", emails, emails)
          .pluck(:kol_id)
      )
    end

    ids = kol_ids.compact.uniq
    ids -= [exclude_id] if exclude_id.present?
    Kol.where(id: ids).order(:id).first
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[
      id name category follower_tier country language owner
      status next_action_at last_contacted_at created_at updated_at
    ]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[kol_contacts kol_messages current_contact current_account]
  end

  private

  # 保存前查重：命中已有 KOL 时拦截并提示归属人
  def check_duplicate
    urls = kol_contacts.map(&:url).map(&:to_s).map(&:strip).reject(&:blank?)
    emails = kol_contacts
      .select { |c| c.platform.to_s == "email" }
      .flat_map { |c| [c.url, c.nickname] }
      .map(&:to_s).map(&:strip).reject(&:blank?)

    dup = Kol.find_duplicate(name: name, contact_urls: urls, contact_emails: emails)
    return if dup.nil?

    errors.add(:base, "该 KOL 已存在（归属人：#{dup.owner}，ID：#{dup.id}），请勿重复录入")
  end
end
