# 大V评论互动模块：大V列表 + 大V发文 + 评论任务
#
# 大V（influencers）：X 平台上的领域大V，评论互动的目标对象。
# 大V发文（influencer_posts）：通过发文获取 API 拉取的大V最新发文（post_id 唯一保证幂等）。
# 评论任务（comment_tasks）：每个「发文 × 评论账号」一条，记录生成内容、下发与执行结果。
class CreateInfluencerCommentModule < ActiveRecord::Migration[6.1]
  def change
    create_table :influencers do |t|
      t.string :username, null: false, comment: '用户名'
      t.string :user_id, comment: '平台用户 ID'
      t.string :platform, null: false, default: 'twitter', comment: '平台（twitter/youtube/instagram 等）'
      t.references :domain, foreign_key: true, comment: '所属领域'
      t.boolean :enabled, null: false, default: true, comment: '是否启用'
      t.text :remark, comment: '备注'
      t.timestamps
    end
    add_index :influencers, :username, unique: true

    create_table :influencer_posts do |t|
      t.references :influencer, null: false, foreign_key: true, comment: '大V'
      t.string :post_id, null: false, comment: '发文 ID'
      t.text :title, comment: '标题/内容'
      t.datetime :posted_at, comment: '发文时间'
      t.timestamps
    end
    add_index :influencer_posts, :post_id, unique: true

    create_table :comment_tasks do |t|
      t.references :influencer_post, null: false, foreign_key: true, comment: '大V发文'
      t.references :account, null: false, foreign_key: true, comment: '评论账号'
      t.text :comment_content, comment: '生成的评论内容'
      t.integer :status, null: false, default: 0, comment: '状态 0待评论 1已下发 2执行中 3成功 4失败'
      t.string :machine_task_id, comment: '机器端任务 ID'
      t.text :error_msg, comment: '失败原因'
      t.datetime :executed_at, comment: '执行时间'
      t.timestamps
    end
    add_index :comment_tasks, [:influencer_post_id, :account_id], unique: true
    add_index :comment_tasks, :status
  end
end
