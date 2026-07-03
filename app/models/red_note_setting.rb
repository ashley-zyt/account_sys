# == Schema Information
#
# Table name: red_note_settings
#
#  id                 :bigint           not null, primary key
#  search_max_results :integer          default(20), not null
#  top_n_by_likes     :integer          default(3),  not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
class RedNoteSetting < ApplicationRecord
  validates :search_max_results, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :top_n_by_likes,     presence: true, numericality: { only_integer: true, greater_than: 0 }

  # 获取当前设置（单例模式，不存在则自动创建默认值）
  def self.current
    first || create!(search_max_results: 20, top_n_by_likes: 3)
  end

  # Rails 单表继承路由自动生成的 URL helper 会用到 model_name，
  # 这里显式声明，避免 STI 推断问题。
  def self.model_name
    ActiveModel::Name.new(self, nil, "RedNoteSetting")
  end
end
