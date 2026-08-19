class CreateMessageTemplatesV2 < ActiveRecord::Migration[6.1]
  def change
    create_table :message_templates do |t|
      t.string :name, null: false, comment: "模板名称"
      # 场景：first_contact 首次建联 / follow_up 跟进询问
      t.integer :scenario, null: false, default: 0, comment: "模板场景"
      t.string :language, null: false, default: "en", comment: "语种"
      t.text :content, null: false, comment: "模板内容（支持变量注入）"

      t.timestamps
    end

    add_index :message_templates, [:scenario, :language]
  end
end
