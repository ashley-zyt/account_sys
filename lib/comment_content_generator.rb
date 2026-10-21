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
      prompt_context = theme_prompts_context(theme)

      <<~PROMPT
        你是海外社交媒体运营专家，负责在 X（Twitter）上对领域大V的推文进行评论互动。

        目标大V的发文内容如下：
        ---
        #{post.title.to_s}
        ---

        你的账号身份：#{account.account_name}（主题：#{account.theme}）

        #{prompt_context}请针对该推文生成一条评论，要求：
        1. 言之有物，紧扣推文的具体观点、数据或信息展开，不要空泛的「好文」「学习了」「great post」。
        2. 提出自己的独立观点或补充信息，能吸引大V回复、引发其他网友点赞和评论，制造围观效果。
        3. 语气自然像真人，不要营销腔、不要广告味、不要表情符号堆砌。
        4. 默认用英文输出（若推文是中文则用中文），1-3 句话，不超过 280 字符。
        5. 只输出评论正文本身，不要任何解释、前缀、引号或 markdown。

        请直接输出评论内容：
      PROMPT
    end

    # 主题的 prompts（Theme.prompts，人工录入）作为评论生成的背景/要求注入。
    def theme_prompts_context(theme)
      prompts = Theme.find_by(name: theme)&.prompts_array || []
      return "" if prompts.empty?
      "该主题的评论要求/背景（评论中自然体现即可，不要照抄）：\n#{prompts.join("\n")}\n\n"
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
