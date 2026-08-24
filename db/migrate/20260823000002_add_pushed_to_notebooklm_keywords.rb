class AddPushedToNotebooklmKeywords < ActiveRecord::Migration[6.1]
  def change
    add_column :notebooklm_keywords, :pushed, :boolean, default: false, null: false, comment: "是否已推送到NotebookLM资源队列"
    add_index :notebooklm_keywords, :pushed unless index_exists?(:notebooklm_keywords, :pushed)
  end
end