class CreateKolVariables < ActiveRecord::Migration[6.1]
  def change
    create_table :kol_variables do |t|
      t.references :kol, type: :bigint, null: false, foreign_key: true
      t.string :variable_key, null: false, comment: "变量标识符"
      t.text :value, comment: "变量值"
      t.timestamps
    end

    add_index :kol_variables, [:kol_id, :variable_key],
              unique: true, name: "index_kol_variables_on_kol_and_key"
  end
end
