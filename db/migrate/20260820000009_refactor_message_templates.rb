class RefactorMessageTemplates < ActiveRecord::Migration[6.1]
  def change
    remove_index :message_templates, [:scenario, :language] if index_exists?(:message_templates, [:scenario, :language])
    remove_column :message_templates, :language if column_exists?(:message_templates, :language)
    remove_column :message_templates, :content if column_exists?(:message_templates, :content)

    add_reference :message_templates, :domain, type: :bigint, null: true, foreign_key: true
    add_column :message_templates, :platform, :integer, comment: "适用平台（空为通用）"
  end
end
