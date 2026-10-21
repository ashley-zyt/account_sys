# 评论内容生成器：根据大V发文内容，通过 Deepseek 生成定制化评论
#
# 针对每条发文、每个账号分别生成内容（账号名/领域作为差异化输入 + 随机 temperature），
# 保证不同账号评论内容各不相同，言之有物、能吸引大V注意并引发互动。
class CommentContentGenerator
  DEEPSEEK_ENDPOINT = 'https://api.deepseek.com/v1/chat/completions'
  MODEL = 'deepseek-chat'

  class << self
    # 为大V发文 + 指定账号生成一条定制评论
    # @param post [InfluencerPost]
    # @param account [Account] 评论账号（用于差异化）
    # @return [String, nil] 评论正文，失败返回 nil
    def generate(post, account, theme = nil)
      prompt = build_prompt(post, account, theme)
      response = call_deepseek(prompt)
      parse_response(response)
    end

    private

    def build_prompt(post, account, theme)
      theme_prompt = CommentThemeConfig.find_by(theme: theme)&.prompt.to_s.strip

      <<~PROMPT
        目标大V的发文内容：
        ---
        #{post.title.to_s}
        ---

        评论账号身份：#{account.account_name}（主题：#{account.theme}）

        #{theme_prompt.presence || '针对以上推文生成一条自然、言之有物、能引发互动的评论。'}

        只输出评论正文本身，不要任何解释、前缀、引号或 markdown。
      PROMPT
    end

    def call_deepseek(prompt)
      api_key = ENV['DEEPSEEK_API_KEY']
      return nil if api_key.blank?

      body = {
        model: MODEL,
        messages: [
          { role: 'system', content: 'You are a social media engagement specialist writing natural, insightful comments.' },
          { role: 'user', content: prompt }
        ],
        temperature: 0.9,
        max_tokens: 300
      }

      response = HTTParty.post(
        DEEPSEEK_ENDPOINT,
        headers: {
          'Content-Type' => 'application/json',
          'Authorization' => "Bearer #{api_key}"
        },
        body: body.to_json,
        timeout: 60
      )
      response.parsed_response
    rescue => e
      Rails.logger.error "[CommentContentGenerator] DeepSeek 请求错误: #{e.message}"
      nil
    end

    def parse_response(response)
      content = response&.dig('choices', 0, 'message', 'content')
      content.to_s.strip.presence
    end
  end
end
