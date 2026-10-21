# 评论内容生成器：根据大V发文内容，通过 Deepseek 生成定制化评论
#
# 针对每条发文生成定制化评论（随机 temperature 保证内容差异），
# 言之有物、能吸引大V注意并引发互动。
class CommentContentGenerator
  DEEPSEEK_ENDPOINT = 'https://api.deepseek.com/v1/chat/completions'
  MODEL = 'deepseek-chat'

  class << self
    # 为大V发文生成一条定制评论
    # @param post [InfluencerPost]
    # @return [String, nil] 评论正文，失败返回 nil
    def generate(post, theme = nil)
      prompt = build_prompt(post, theme)
      response = call_deepseek(prompt)
      parse_response(response)
    end

    private

    def build_prompt(post, theme)
      theme_prompt = CommentThemeConfig.find_by(theme: theme)&.prompt.to_s.strip

      <<~PROMPT
        目标大V的发文内容：
        ---
        #{post.title.to_s}
        ---

        #{theme_prompt}

        请用与推文相同的语言输出评论；若推文语言无法判断，默认使用英文，不要用中文。

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
