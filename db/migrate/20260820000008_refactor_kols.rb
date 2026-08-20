class RefactorKols < ActiveRecord::Migration[6.1]
  def change
    # 移除旧字段及对应索引
    remove_index :kols, :category if index_exists?(:kols, :category)
    remove_index :kols, :language if index_exists?(:kols, :language)
    remove_column :kols, :category if column_exists?(:kols, :category)
    remove_column :kols, :follower_tier if column_exists?(:kols, :follower_tier)
    remove_column :kols, :language if column_exists?(:kols, :language)

    # 领域 / 语言改为字典引用
    add_reference :kols, :domain, type: :bigint, null: true, foreign_key: true
    add_reference :kols, :language, type: :bigint, null: true, foreign_key: true

    # 粉丝量级：左闭右开区间（max 为空表示“以上”）
    add_column :kols, :follower_min, :bigint, comment: "粉丝量级下限（含）"
    add_column :kols, :follower_max, :bigint, comment: "粉丝量级上限（不含，空为以上）"

    # 变量待补全标记（自动触达时缺变量则跳过并标记）
    add_column :kols, :variables_incomplete, :boolean, null: false, default: false, comment: "变量待补全"
  end
end
