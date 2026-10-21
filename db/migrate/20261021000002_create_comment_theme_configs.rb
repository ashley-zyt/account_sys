# 评论互动 prompt 配置表：每个主题对应一类「针对大V发文生成互动性评论」的 prompt。
# 与 themes.prompts（发文字标题用）完全独立，避免混淆。
class CreateCommentThemeConfigs < ActiveRecord::Migration[6.1]
  def change
    create_table :comment_theme_configs do |t|
      t.string :theme, null: false, comment: '主题名（对应 Account.theme / Influencer.theme）'
      t.text :prompt, comment: '评论互动 prompt（每行一条）'
      t.timestamps
    end
    add_index :comment_theme_configs, :theme, unique: true
  end
end
