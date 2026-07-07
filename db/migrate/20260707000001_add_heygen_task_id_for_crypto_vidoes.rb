class AddHeygenTaskIdForCryptoVidoes < ActiveRecord::Migration[6.1]
  def change
    add_column :crypto_videos, :heygen_task_id, :integer, comment: "Heygen任务ID" unless column_exists?(:crypto_videos, :heygen_task_id)
    add_index :crypto_videos, :heygen_task_id unless index_exists?(:crypto_videos, :heygen_task_id)
  end
end
