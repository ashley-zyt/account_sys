class Kol < ApplicationRecord
  has_many :kol_platform_accounts, dependent: :destroy
  has_many :conversations, dependent: :destroy

  validates :kol_name, presence: true
end