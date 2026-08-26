# == Schema Information
#
# Table name: kols
#
#  id                                                       :bigint           not null, primary key
#  country(所在国家/地区)                                   :string(255)
#  follower_max(粉丝量级上限（不含，空为以上）)             :bigint
#  follower_min(粉丝量级下限（含）)                         :bigint
#  last_contacted_at(最后一次触达时间)                      :datetime
#  name(KOL名称/常用用户名)                                 :string(255)      not null
#  next_action_at(下次可执行自动化动作的时间（等待期结束）) :datetime
#  notes(备注)                                              :text(65535)
#  owner(归属人（负责人）)                                  :string(255)      not null
#  status(KOL业务生命周期状态)                              :integer          default("reserved"), not null
#  variables_incomplete(变量待补全)                         :boolean          default(FALSE), not null
#  created_at                                               :datetime         not null
#  updated_at                                               :datetime         not null
#  current_account_id(当前分配的内部账号ID)                 :bigint
#  current_contact_id(当前正在触达的联系方式ID)             :bigint
#  domain_id                                                :bigint
#  language_id                                              :bigint
#
# Indexes
#
#  index_kols_on_domain_id       (domain_id)
#  index_kols_on_language_id     (language_id)
#  index_kols_on_name            (name)
#  index_kols_on_next_action_at  (next_action_at)
#  index_kols_on_owner           (owner)
#  index_kols_on_status          (status)
#
# Foreign Keys
#
#  fk_rails_...  (domain_id => domains.id)
#  fk_rails_...  (language_id => languages.id)
#
class Kol < ApplicationRecord
  has_many :kol_contacts, dependent: :destroy
  has_many :kol_messages, dependent: :destroy
  has_many :kol_variables, dependent: :destroy

  belongs_to :current_contact, class_name: "KolContact", optional: true
  belongs_to :current_account, class_name: "Account", optional: true
  belongs_to :domain, optional: true
  belongs_to :language, optional: true

  accepts_nested_attributes_for :kol_contacts, allow_destroy: true, reject_if: proc { |attrs| attrs["nickname"].blank? && attrs["url"].blank? }

  # 第一层：KOL 业务生命周期状态
  enum status: {
    reserved: 0,              # 未开始
    pending: 1,               # 待联系
    contacting: 2,            # 联系中
    replied_unprocessed: 3,   # 待回复
    negotiating: 4,           # 洽谈中
    cooperating: 5,           # 已合作
    failed: 6,                # 已拒绝
    unresponsive: 7           # 未回复
  }

  # KOL 业务状态中文标签（表单下拉与展示共用）
  STATUS_LABELS = {
    "reserved"            => "未开始",
    "pending"             => "待联系",
    "contacting"          => "联系中",
    "replied_unprocessed" => "待回复",
    "negotiating"         => "人工洽谈中",
    "cooperating"         => "已合作",
    "failed"              => "已拒绝",
    "unresponsive"        => "未回复"
  }.freeze

  # 允许运营在快捷区直接切换的状态（其余为系统自动流转，人工改容易混乱）
  MANUAL_STATUS_KEYS = %w[reserved negotiating cooperating failed unresponsive].freeze

  def status_label
    STATUS_LABELS[status] || status.to_s
  end

  # 粉丝量级区间（左闭右开）
  FOLLOWER_TIERS = [
    { label: "0万-10万",     min: 0,           max: 100_000 },
    { label: "10万-50万",    min: 100_000,     max: 500_000 },
    { label: "50万-100万",   min: 500_000,     max: 1_000_000 },
    { label: "100万-500万",  min: 1_000_000,   max: 5_000_000 },
    { label: "500万以上",    min: 5_000_000,   max: nil }
  ].freeze

  validates :name, presence: true
  validates :owner, presence: true
  validates :domain, presence: { message: "所属领域不能为空" }

  validate :check_duplicate

  # 可发信且未失效的联系渠道，按优先级升序
  def active_contacts
    kol_contacts.where(status: :active)
                .where(messaging_enabled: true)
                .order(priority: :asc, id: :asc)
  end

  def enqueue!
    return false unless ready_for_outreach?
    update!(status: :pending, next_action_at: nil)
    true
  end

  def dequeue!
    update!(status: :reserved, next_action_at: nil)
  end

  def latest_incoming_reply
    kol_messages.where(direction: :incoming, status: :replied).order(id: :desc).first
  end

  def latest_outgoing_message
    kol_messages.where(direction: :outgoing).order(id: :desc).first
  end

  # 粉丝量级中文标签
  def follower_tier_label
    return nil if follower_min.nil? && follower_max.nil?
    tier = FOLLOWER_TIERS.find { |t| t[:min] == follower_min && t[:max] == follower_max }
    tier ? tier[:label] : nil
  end

  # ===== 变量值（键值对） =====

  def variable_value(key)
    kol_variables.find_by(variable_key: key.to_s)&.value
  end

  # 返回缺失的变量标识符列表
  def missing_variables(keys)
    Array(keys).map(&:to_s).reject { |k| variable_value(k).present? }
  end

  # 写入/清空单个变量值
  def set_variable!(key, value)
    v = value.to_s.strip
    if v.present?
      kol_variables.find_or_initialize_by(variable_key: key.to_s).update!(value: v)
    else
      kol_variables.where(variable_key: key.to_s).delete_all
    end
  end

  # 批量同步变量值（{ key => value }）
  def sync_variables!(hash)
    (hash || {}).each { |key, value| set_variable!(key, value) }
  end

  # 首次建联所需变量标识符（录入时按领域匹配；平台在发送时才参与匹配）
  def required_entry_variable_keys
    return [] if domain_id.blank?
    MessageTemplate.suggested_variables(scenario: :first_contact, platforms: [], domain_id: domain_id)
  end

  # 缺失的首次建联变量标识符列表
  def missing_entry_variables
    missing_variables(required_entry_variable_keys)
  end

  def variables_complete?
    missing_entry_variables.empty?
  end

  # 是否存在可被自动化触达的联系方式（有效 + 可发私信 + 已接通平台）
  def has_outreachable_contacts?
    kol_contacts.any? do |c|
      c.active? && c.messaging_enabled? && KolAccountAllocator.supported_platform?(c.platform)
    end
  end

  # 是否具备进入自动化触达队列的条件
  def ready_for_outreach?
    variables_complete? && has_outreachable_contacts?
  end

  # 是否存在「联系方式缺少 url」的记录（旧数据补录排查用）
  def has_missing_contact_url?
    kol_contacts.any? { |c| c.url.blank? }
  end

  scope :pending_queue, -> {
    where(status: :pending)
      .where(variables_incomplete: false)
      .where("next_action_at IS NULL OR next_action_at <= ?", Time.current)
      .order(created_at: :asc)
  }

  # 全局查重：命中已有 KOL 时返回 { kind:, value:, kol: }，未命中返回 nil
  # kind: :url（主页链接重复）/ :nickname（昵称重复）
  # exclude_id: 需要排除的 KOL ID（更新时排除自身，避免把自己当成重复）
  def self.find_duplicate(contact_urls: [], contact_nicknames: [], exclude_id: nil)
    urls = Array(contact_urls).map(&:to_s).map(&:strip).reject(&:blank?).uniq
    nicknames = Array(contact_nicknames).map(&:to_s).map(&:strip).reject(&:blank?).uniq

    base = exclude_id.present? ? KolContact.where.not(kol_id: exclude_id) : KolContact.all

    url_hit = urls.any? ? base.where("url IN (?)", urls).order(:id).first : nil
    return { kind: :url, value: url_hit.url, kol: url_hit.kol } if url_hit

    nickname_hit = nicknames.any? ? base.where("nickname IN (?)", nicknames).order(:id).first : nil
    return { kind: :nickname, value: nickname_hit.nickname, kol: nickname_hit.kol } if nickname_hit

    nil
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[
      id name domain_id language_id country owner
      status follower_min follower_max variables_incomplete
      next_action_at last_contacted_at created_at updated_at
    ]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[kol_contacts kol_messages kol_variables current_contact current_account domain language]
  end

  private

  # 保存前查重（新建 + 更新均校验）：命中已有 KOL 时拦截，并说明是「昵称」还是「主页链接」重复
  def check_duplicate
    urls = kol_contacts.map { |c| c.url.to_s.strip }.reject(&:blank?)
    nicknames = kol_contacts.map { |c| c.nickname.to_s.strip }.reject(&:blank?)

    dup = Kol.find_duplicate(contact_urls: urls, contact_nicknames: nicknames, exclude_id: id)
    return if dup.nil?

    if dup[:kind] == :nickname
      errors.add(:base, "该 KOL 已存在：昵称「#{dup[:value]}」重复（归属人：#{dup[:kol].owner}，ID：#{dup[:kol].id}），请勿重复录入")
    else
      errors.add(:base, "该 KOL 已存在：主页链接「#{dup[:value]}」重复（归属人：#{dup[:kol].owner}，ID：#{dup[:kol].id}），请勿重复录入")
    end
  end
end
