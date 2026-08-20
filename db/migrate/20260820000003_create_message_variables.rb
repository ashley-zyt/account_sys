class CreateMessageVariables < ActiveRecord::Migration[6.1]
  def change
    create_table :message_variables do |t|
      t.string :identifier, null: false, comment: "变量标识符（如 name/email）"
      t.string :name, null: false, comment: "变量中文名"
      t.text :description, comment: "变量说明"
      t.timestamps
    end

    add_index :message_variables, :identifier, unique: true
  end
end
