class CreateMessageTemplateVariables < ActiveRecord::Migration[6.1]
  def change
    create_table :message_template_variables do |t|
      t.references :message_template, type: :bigint, null: false, foreign_key: true
      t.references :message_variable, type: :bigint, null: false, foreign_key: true
      t.timestamps
    end

    add_index :message_template_variables, [:message_template_id, :message_variable_id],
              unique: true, name: "index_mtvars_on_template_and_variable"
  end
end
