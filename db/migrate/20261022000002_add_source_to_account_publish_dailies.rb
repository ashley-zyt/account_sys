class AddSourceToAccountPublishDailies < ActiveRecord::Migration[6.1]
  def change
    # default 用 backfill(1)：历史数据均来自旧的 build_for/classify 事后反推，
    # 新代码会显式写 realtime(当场记录) 或 backfill(反推兜底)。
    add_column :account_publish_dailies, :source, :integer, default: 1, null: false,
              comment: '记录来源 0当场记录 1反推兜底'
    add_index :account_publish_dailies, [:stat_date, :source],
              name: 'index_account_publish_dailies_on_stat_date_and_source'
  end
end
