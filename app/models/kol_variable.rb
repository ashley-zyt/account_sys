class KolVariable < ApplicationRecord
  belongs_to :kol

  validates :variable_key, presence: true
  validates :variable_key, uniqueness: { scope: :kol_id }
end
