# == Schema Information
#
# Table name: browser_occupations
#
#  id                                                             :bigint           not null, primary key
#  expires_at(占用过期时间（崩溃兜底，正常走 release）)           :datetime         not null
#  machine_ip(所属运营机器 IP/域名)                               :string(255)      not null
#  operation(占用类型：publish/collect/nurture/kol/domestic)      :string(255)      not null
#  profile_name(指纹浏览器名称（冗余，便于日志/排查）)            :string(255)
#  released_at(释放时间；释放后保留 30s 作为冷却标记，之后被清理) :datetime
#  resource_key(资源唯一标识（profile:<profile_name>）)           :string(255)      not null
#  task_ref(任务引用（如 MoveTask#123，仅日志/排查用）)           :string(255)
#  created_at                                                     :datetime         not null
#  updated_at                                                     :datetime         not null
#
# Indexes
#
#  index_browser_occupations_on_expires_at                    (expires_at)
#  index_browser_occupations_on_machine_ip                    (machine_ip)
#  index_browser_occupations_on_resource_key                  (resource_key)
#  index_browser_occupations_on_resource_key_and_released_at  (resource_key,released_at)
#
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

  # 以 profile_name 生成 resource_key（与机器端共通的标识）
  def self.key_for_profile(profile_name)
    "profile:#{profile_name}"
  end

  # 按 browser 生成 resource_key（内部统一走 profile_name）
  def self.key_for_browser(browser)
    key_for_profile(browser.profile_name)
  end

  # 按虚拟资源名生成 resource_key（如 domestic01，本质也是 profile_name）
  def self.key_for_virtual(name)
    key_for_profile(name)
  end
end
