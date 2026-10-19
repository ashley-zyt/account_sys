# 大V发文获取适配层
#
# 职责：从发文获取 API 拉取启用大V的最新发文并落库（post_id 唯一保证幂等）。
#
# 当前发文 API 尚未确定，fetch_posts_for 为占位实现（返回空）。
# 接入真实 API 时，只需实现 fetch_posts_for（或改写 fetch_latest_posts），
# 上层 CommentScheduler 无需改动。
class InfluencerPostFetcher
  class << self
    # 获取所有启用大V的最新发文，落库。
    # @return [Integer] 新入库的发文条数
    def fetch_latest_posts
      influencers = Influencer.enabled
      return 0 if influencers.empty?

      created = 0
      influencers.each do |influencer|
        posts = fetch_posts_for(influencer)
        Array(posts).each do |p|
          next if p.blank? || p[:post_id].blank?

          record = InfluencerPost.find_or_initialize_by(post_id: p[:post_id])
          next if record.persisted? # 已存在，跳过（幂等）

          record.assign_attributes(
            influencer_id: influencer.id,
            title: p[:title],
            posted_at: p[:posted_at]
          )
          created += 1 if record.save
        end
      end
      created
    rescue => e
      Rails.logger.error "[InfluencerPostFetcher] 获取发文异常: #{e.message}"
      0
    end

    # 获取单个大V的最新发文。
    # TODO: 接入真实发文获取 API（X 平台大V时间线）。
    # @param influencer [Influencer]
    # @return [Array<Hash>] [{ post_id:, title:, posted_at: }]
    def fetch_posts_for(influencer)
      # 占位实现：API 未确定，返回空
      []
    end
  end
end
