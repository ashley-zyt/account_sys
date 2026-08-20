# == Schema Information
#
# Table name: kol_variables
#
#  id                       :bigint           not null, primary key
#  value(变量值)            :text(65535)
#  variable_key(变量标识符) :string(255)      not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  kol_id                   :bigint           not null
#
# Indexes
#
#  index_kol_variables_on_kol_and_key  (kol_id,variable_key) UNIQUE
#  index_kol_variables_on_kol_id       (kol_id)
#
# Foreign Keys
#
#  fk_rails_...  (kol_id => kols.id)
#
class KolVariable < ApplicationRecord
  belongs_to :kol

  validates :variable_key, presence: true
  validates :variable_key, uniqueness: { scope: :kol_id }
end
