# == Schema Information
#
# Table name: browser_occupations
#
#  id           :bigint           not null, primary key
#  resource_key :string(255)      not null  # browser:<id> 或 virtual:<key>
#  machine_ip   :string(255)      not null
#  profile_name :string(255)
#  operation    :string(255)      not null  # publish/collect/nurture/kol/domestic
#  task_ref     :string(255)
#  expires_at   :datetime         not null
#  released_at  :datetime
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
# 临时占用登记（用完即删/短冷却），非长期数据。并发控制见 BrowserOccupationManager。
class BrowserOccupation < ApplicationRecord
  OPERATIONS = %w[publish collect nurture kol domestic].freeze

  validates :resource_key, :machine_ip, :operation, presence: true

  scope :active, -> { where(released_at: nil) }
  scope :released, -> { where.not(released_at: nil) }

  # 是否仍处于活跃占用
  def active?
    released_at.nil?
  end

  # 是否处于释放后冷却期（由 Manager 的 COOLDOWN_SECONDS 决定）
  def cooling?(cooldown_seconds: 30)
    released_at.present? && released_at > cooldown_seconds.seconds.ago
  end

  # 按 browser 生成 resource_key
  def self.key_for_browser(browser)
    "browser:#{browser.id}"
  end

  # 按 browser_id 生成 resource_key（供回传接口用）
  def self.key_for_browser_id(id)
    "browser:#{id}"
  end

  # 按虚拟资源名生成 resource_key（如 domestic01）
  def self.key_for_virtual(name)
    "virtual:#{name}"
  end
end
