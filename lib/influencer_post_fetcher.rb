# 大V发文获取适配层
#
# 职责：从发文获取 API 拉取启用大V的最新发文并落库（post_id 唯一保证幂等）。
#
# API：GET http://116.62.222.214:30234/api/get_7days_yh_datas
#   参数：
#     - account_type: 2（固定）
#     - user_id:      已启用大V的 user_id，多个用英文逗号分隔（如 1,2,3）
#     - before_t:     时间戳（默认一小时前），只拉取该时间之后（近一小时）已发的文
#   返回：{ "status":"success", "data":[ { "id":推文ID, "title":内容, "created_time":发文时间戳,
#          "user_id":大V用户ID, "is_retweeted":是否转发, ... } ] }
require 'httparty'

class InfluencerPostFetcher
  API_BASE = 'http://116.62.222.214:30234/api/get_7days_yh_datas'
  ACCOUNT_TYPE = 2

  class << self
    # 批量获取所有启用大V的最新发文并落库。
    # @return [Integer] 新入库的发文条数
    def fetch_latest_posts
      influencers = Influencer.enabled
      return 0 if influencers.empty?

      user_ids = influencers.map { |i| i.user_id.to_s.strip }.reject(&:empty?)
      return 0 if user_ids.empty?

      posts = fetch_from_api(user_ids)
      return 0 if posts.empty?

      # user_id（字符串）→ influencer，用于把发文归属到对应大V
      influencer_by_user_id = {}
      influencers.each { |i| influencer_by_user_id[i.user_id.to_s] = i if i.user_id.present? }

      created = 0
      posts.each do |p|
        next unless p.is_a?(Hash)
        next if p['is_retweeted'] # 转发推文直接过滤，只保留原创发文供评论互动

        post_id = p['id'].to_s
        next if post_id.blank? || post_id == '0'

        influencer = influencer_by_user_id[p['user_id'].to_s]
        next if influencer.nil? # 发文不属于任何启用大V，跳过

        record = InfluencerPost.find_or_initialize_by(post_id: post_id)
        next if record.persisted? # 已存在，跳过（幂等）

        record.assign_attributes(
          influencer_id: influencer.id,
          title: p['title'].to_s,
          source_url: p['source_url'].to_s,
          posted_at: parse_time(p['created_time'])
        )
        created += 1 if record.save
      end
      created
    rescue => e
      Rails.logger.error "[InfluencerPostFetcher] 获取发文异常: #{e.message}"
      0
    end

    private

    # 调用发文获取 API，返回 data 数组
    def fetch_from_api(user_ids)
      before_t = 1.hour.ago.to_i
      response = HTTParty.get(
        API_BASE,
        query: { account_type: ACCOUNT_TYPE, user_id: user_ids.join(','), before_t: before_t },
        timeout: 30
      )
      body = response.parsed_response
      return [] unless body.is_a?(Hash)
      return [] unless body['status'].to_s == 'success'
      Array(body['data'])
    rescue => e
      Rails.logger.error "[InfluencerPostFetcher] API 请求异常: #{e.message}"
      []
    end

    # Unix 时间戳 → Time
    def parse_time(ts)
      return nil if ts.blank?
      Time.at(ts.to_i)
    rescue
      nil
    end
  end
end
