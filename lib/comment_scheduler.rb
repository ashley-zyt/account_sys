# 大V评论互动调度器
#
# 流程（每半小时跑一次）：
#   1. InfluencerPostFetcher 获取启用大V的最新发文并落库
#   2. 对新发文（尚未生成评论任务的），分配一个「当天未满上限」的同主题账号生成定制评论
#   3. 下发 pending 评论任务到机器端浏览器
#
# 主题粒度：账号按发文大V的 theme（Account.theme）匹配，评论 prompt 用主题对应的 CommentThemeConfig。
class CommentScheduler
  # 单个账号每天最多评论互动的发文数
  MAX_COMMENTS_PER_DAY = 2

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

    # 为一条发文，分配「当天评论数未满上限」的同主题账号生成一条评论任务。
    # 主题取发文对应大V的 theme；账号 = Account.theme 匹配；prompt 用主题对应的 CommentThemeConfig。
    # 一条发文只用一个账号评论；每个账号每天最多评论 MAX_COMMENTS_PER_DAY 条发文。
    # @return [Integer] 新建任务数（0 或 1）
    def generate_tasks_for(post)
      theme = post.influencer&.theme
      return 0 if theme.blank?

      # 未配置该主题的评论 prompt 时，不生成评论任务，避免无针对性的兜底内容入库
      unless CommentThemeConfig.find_by(theme: theme)&.prompt.present?
        Rails.logger.info "[CommentScheduler] 跳过发文 #{post.id}：主题 #{theme} 未配置评论 prompt"
        return 0
      end

      account = pick_available_account(theme)
      return 0 if account.nil?

      content = CommentContentGenerator.generate(post, account, theme)
      return 0 if content.blank?

      CommentTask.create!(
        influencer_post: post,
        account: account,
        comment_content: content,
        status: :pending
      )
      1
    rescue ActiveRecord::RecordNotUnique
      0
    end

    # 选一个「当天已生成评论任务数 < MAX_COMMENTS_PER_DAY」的同主题账号。
    # 按当天任务数升序选择，实现账号间均衡分配。
    def pick_available_account(theme)
      accounts = themed_accounts(theme).to_a
      return nil if accounts.empty?

      counts = CommentTask.where(account_id: accounts.map(&:id))
                          .where(created_at: Time.current.beginning_of_day..Time.current.end_of_day)
                          .group(:account_id).count

      accounts.sort_by { |a| counts[a.id].to_i }
              .find { |a| counts[a.id].to_i < MAX_COMMENTS_PER_DAY }
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

    # 指定主题 + X 平台 + 正常状态的账号（Account.theme 直接匹配主题）
    def themed_accounts(theme)
      Account.active
             .where(platform: Account.platforms[:twitter])
             .where(theme: theme)
    end

    def setup_logger(file)
      logger = ActiveSupport::Logger.new(File.join(Rails.root, 'log', file))
      logger.formatter = Rails.logger.formatter
      Rails.logger = logger
    end
  end
end
