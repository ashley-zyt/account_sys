class DropKolTables < ActiveRecord::Migration[6.1]
  def up
    # 按外键依赖顺序删除：先删有外键的子表，再删父表，避免外键约束阻止 drop
    drop_table :conversation_messages   # 外键 → conversations
    drop_table :conversations           # 引用 kol / kol_platform_accounts（仅索引，无外键约束）
    drop_table :kol_platform_accounts   # 外键 → kols
    drop_table :message_templates
    drop_table :kols
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "KOL 模块数据表已删除，无法回滚；如需恢复请基于原有 create 迁移重新设计"
  end
end