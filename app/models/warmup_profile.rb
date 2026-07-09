# == Schema Information
#
# Table name: warmup_profiles
#
#  id                :bigint           not null, primary key
#  account_id        :bigint           not null, unique
#  last_warmup_at    :datetime
#  warmup_enabled    :boolean          default(true)
#  warmup_frequency  :string           default("weekly")
#  warmup_status     :string
#  warmup_batch      :integer          default(0)
#  machine           :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#

class WarmupProfile < ApplicationRecord
  belongs_to :account

  validates :account_id, uniqueness: true

  def warmup_due?
    return false unless warmup_enabled
    return true if last_warmup_at.nil?

    case warmup_frequency
    when 'daily'
      last_warmup_at < Time.current - 1.day
    when 'weekly'
      last_warmup_at < Time.current - 1.week
    when 'biweekly'
      last_warmup_at < Time.current - 2.weeks
    else
      last_warmup_at < Time.current - 1.week
    end
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[
      id
      account_id
      last_warmup_at
      warmup_enabled
      warmup_frequency
      warmup_status
      warmup_batch
      machine
      created_at
      updated_at
    ]
  end

  def self.ransackable_associations(auth_object = nil)
    ["account"]
  end
end