class AddDomainIdToThemes < ActiveRecord::Migration[6.1]
  def change
    add_reference :themes, :domain, type: :bigint, null: true, foreign_key: true
  end
end
