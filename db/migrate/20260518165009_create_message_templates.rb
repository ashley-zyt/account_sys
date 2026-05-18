class CreateMessageTemplates < ActiveRecord::Migration[6.1]
  def change
    create_table :message_templates do |t|
      t.integer :platform,
                null: false,
                comment: "平台"

      t.integer :template_type,
                null: false,
                comment: "模板类型"

      t.string :language,
               default: "en",
               comment: "语言"

      t.text :content,
             null: false,
             comment: "模板内容"

      t.timestamps
    end

    add_index :message_templates, :platform
    add_index :message_templates, :template_type
  end
end