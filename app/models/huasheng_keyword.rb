# == Schema Information
#
# Table name: huasheng_keywords
#
#  id          :bigint           not null, primary key
#  theme       :string(255)      not null
#  keyword     :string(255)      not null
#  status      :integer          default(0)
#  task_id     :string(255)
#  result_data :text(65535)
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_huasheng_keywords_on_status           (status)
#  index_huasheng_keywords_on_theme            (theme)
#  index_huasheng_keywords_on_theme_and_status  (theme, status)
#
class HuashengKeyword < ApplicationRecord
  STATUS_NAMES = {
    0 => "未启动",
    1 => "待执行",
    2 => "执行中",
    3 => "执行完成",
    4 => "任务失败"
  }.freeze

  validates :theme, :keyword, presence: true

  scope :by_theme, ->(theme) { where(theme: theme) if theme.present? }
  scope :by_status, ->(status) { where(status: status) if status.present? }

  def self.ransackable_attributes(auth_object = nil)
    %w[id theme keyword status task_id created_at updated_at]
  end

  def status_name
    STATUS_NAMES[status] || "未知"
  end
end
