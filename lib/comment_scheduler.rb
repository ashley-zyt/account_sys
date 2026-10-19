# 大V评论互动调度器
#
# 流程（每半小时跑一次）：
#   1. InfluencerPostFetcher 获取启用大V的最新发文并落库
#   2. 对新发文（尚未生成评论任务的），为每个「数字货币领域 + X 平台 + 正常」账号生成定制评论
#   3. 下发 pending 评论任务到机器端浏览器
class CommentScheduler
  DIGITAL_CURRENCY_DOMAIN = '数字货币'

  class << self
    def run
      setup_logger('comment_scheduler.log')
      Rails.logger.info "[CommentScheduler] 开始评论互动扫描"

      # 1. 获取最新发文
      created = InfluencerPostFetcher.fetch_latest_posts
      Rails.logger.info "[CommentScheduler] 新获取发文 #{created} 条"

      # 2. 为新发文生成评论任务（只对还没生成过任务的新发文）
      new_posts = InfluencerPost.left_joins(:comment_tasks).where(comment_tasks: { id: nil })
      generated = 0
      new_posts.find_each do |post|
        generated += generate_tasks_for(post)
      end
      Rails.logger.info "[CommentScheduler] 为新发文生成评论任务 #{generated} 条"

      # 3. 下发 pending 任务
      dispatch_pending_tasks

      Rails.logger.info "[CommentScheduler] 评论互动扫描完成"
    end

    # 为一条发文，给所有数字货币领域 X 账号生成评论任务（内容各自不同）
    # @return [Integer] 新建任务数
    def generate_tasks_for(post)
      accounts = digital_currency_accounts
      return 0 if accounts.empty?

      created = 0
      accounts.find_each do |account|
        content = CommentContentGenerator.generate(post, account)
        next if content.blank?

        CommentTask.create!(
          influencer_post: post,
          account: account,
          comment_content: content,
          status: :pending
        )
        created += 1
      rescue ActiveRecord::RecordNotUnique
        # 该「发文 × 账号」已有任务，跳过
      end
      created
    end

    # 下发所有 pending 评论任务到机器端
    def dispatch_pending_tasks
      CommentTask.where(status: :pending).find_each do |task|
        result = CommentPublisher.dispatch(task)
        if result[:success]
          task.update!(status: :queued, machine_task_id: result[:task_id])
        else
          # 机器端评论接口未接入 / 下发失败：保持 pending，等待接口就绪后下次重试
          Rails.logger.warn "[CommentScheduler] 评论任务 #{task.id} 下发失败：#{result[:error]}"
        end
      end
    end

    # 数字货币领域 + X 平台 + 正常状态的账号
    def digital_currency_accounts
      domain = Domain.find_by(name: DIGITAL_CURRENCY_DOMAIN)
      return Account.none unless domain

      theme_names = Theme.where(domain_id: domain.id).pluck(:name)
      return Account.none if theme_names.empty?

      Account.active
             .where(platform: Account.platforms[:twitter])
             .where(theme: theme_names)
    end

    def setup_logger(file)
      logger = ActiveSupport::Logger.new(File.join(Rails.root, 'log', file))
      logger.formatter = Rails.logger.formatter
      Rails.logger = logger
    end
  end
end
