# == Schema Information
#
# Table name: machines
#
#  id                                           :bigint           not null, primary key
#  host(当前地址（IP或域名），换服务器只改这里) :string(255)      not null
#  name(机器稳定标识（如机器A/机器B）)          :string(255)      not null
#  remark(备注)                                 :string(255)
#  created_at                                   :datetime         not null
#  updated_at                                   :datetime         not null
#
# Indexes
#
#  index_machines_on_name  (name) UNIQUE
#
class Machine < ApplicationRecord
  has_many :browsers

  validates :name, presence: true, uniqueness: true
  validates :host, presence: true

  def self.ransackable_attributes(auth_object = nil)
    %w[id name host remark created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[browsers]
  end
end
