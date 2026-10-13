class ChangeKolFollowerTierToText < ActiveRecord::Migration[6.1]
  def up
    add_column :kols, :follower_tier, :string, comment: "粉丝量级（自由文本）"

    # 迁移旧数据：follower_min/max 组合映射为友好文本标签；非标准区间则用「min-max / min以上」兜底
    execute <<~SQL
      UPDATE kols
      SET follower_tier = CASE
        WHEN follower_min = 0          AND follower_max = 100000   THEN '0万-10万'
        WHEN follower_min = 100000     AND follower_max = 500000   THEN '10万-50万'
        WHEN follower_min = 500000     AND follower_max = 1000000  THEN '50万-100万'
        WHEN follower_min = 1000000    AND follower_max = 5000000  THEN '100万-500万'
        WHEN follower_min = 5000000    AND follower_max IS NULL    THEN '500万以上'
        WHEN follower_min IS NOT NULL AND follower_max IS NOT NULL THEN CONCAT(follower_min, '-', follower_max)
        WHEN follower_min IS NOT NULL AND follower_max IS NULL     THEN CONCAT(follower_min, '以上')
        ELSE NULL
      END
      WHERE follower_min IS NOT NULL OR follower_max IS NOT NULL
    SQL

    remove_column :kols, :follower_min
    remove_column :kols, :follower_max
  end

  def down
    add_column :kols, :follower_min, :bigint, comment: "粉丝量级下限（含）"
    add_column :kols, :follower_max, :bigint, comment: "粉丝量级上限（不含，空为以上）"
    remove_column :kols, :follower_tier
  end
end
