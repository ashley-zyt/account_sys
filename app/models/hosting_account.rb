# == Schema Information
#
# Table name: hosting_accounts
#
#  id                                                          :bigint           not null, primary key
#  platform(平台（twitter/youtube/tiktok/instagram/facebook）) :string(255)      not null
#  publish_channel(发布渠道（postpeer/postforme/x）)           :string(255)
#  remark(备注)                                                :text(65535)
#  resource_queue(资源队列（WorkMode key，如 move/jianying）)  :string(255)
#  status(状态 0托管中 1暂停 2终止)                            :integer          default("active"), not null
#  theme(主题（用于资源分配匹配）)                             :string(255)
#  created_at                                                  :datetime         not null
#  updated_at                                                  :datetime         not null
#  client_id(归属客户)                                         :bigint           not null
#  homepage_url(账号主页链接)                                  :string(255)
#  username(账号用户名)                                        :string(255)
#
# Indexes
#
#  index_hosting_accounts_on_client_id  (client_id)
#  index_hosting_accounts_on_platform   (platform)
#  index_hosting_accounts_on_theme      (theme)
#
# Foreign Keys
#
#  fk_rails_...  (client_id => clients.id)
#
class HostingAccount < ApplicationRecord
  belongs_to :client
  has_many :hosting_publish_tasks, dependent: :destroy
  has_one :postpeer_account, dependent: :destroy
  has_one :postforme_account, dependent: :destroy
  has_one :x_credential, dependent: :destroy

  enum status: { active: 0, paused: 1, terminated: 2 }

  # 可发布的托管账号：托管中 + 客户合作中（客户暂停/终止后，其下托管账号不再参与发布）
  scope :publishable, -> { joins(:client).where(status: :active, clients: { status: :active }) }

  validates :client_id, presence: true
  validates :platform, presence: true

  # 该托管账号当前是否可发布（账号与客户都处于正常状态）
  def publishable?
    active? && (client&.active? || false)
  end

  # 该托管账号指定的资源队列对应的 WorkMode（resource_queue 存 WorkMode key）
  def work_mode
    WorkMode.find(resource_queue)
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[id client_id platform theme resource_queue publish_channel status username homepage_url remark created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[client hosting_publish_tasks postpeer_account postforme_account x_credential]
  end
end
