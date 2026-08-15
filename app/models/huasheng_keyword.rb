# == Schema Information
#
# Table name: huasheng_keywords
#
#  id                                                            :bigint           not null, primary key
#  keyword(关键词)                                               :string(255)      not null
#  result_data(采集结果数据（JSON）)                             :text(65535)
#  status(任务状态：0未启动 1待执行 2执行中 3执行完成 4任务失败) :integer          default(0)
#  theme(主题)                                                   :string(255)      not null
#  created_at                                                    :datetime         not null
#  updated_at                                                    :datetime         not null
#  task_id(远程任务ID)                                           :string(255)
#
# Indexes
#
#  index_huasheng_keywords_on_status            (status)
#  index_huasheng_keywords_on_theme             (theme)
#  index_huasheng_keywords_on_theme_and_status  (theme,status)
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
