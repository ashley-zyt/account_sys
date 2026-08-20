class CreateMessageTemplateVersions < ActiveRecord::Migration[6.1]
  def change
    create_table :message_template_versions do |t|
      t.references :message_template, type: :bigint, null: false, foreign_key: true
      t.references :language, type: :bigint, null: false, foreign_key: true
      t.text :content, null: false, comment: "模板内容（支持 ${变量} 注入）"
      t.timestamps
    end

    add_index :message_template_versions, [:message_template_id, :language_id],
              unique: true, name: "index_mtv_on_template_and_language"
  end
end
