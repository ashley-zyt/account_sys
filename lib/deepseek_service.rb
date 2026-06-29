# app/services/deepseek_service.rb
require "openai"

class DeepseekService
  attr_reader :client

  def initialize
    @client = OpenAI::Client.new(
      access_token: ENV["DEEPSEEK_API_KEY"],
      uri_base: ENV["DEEPSEEK_BASE_URL"] || "https://api.deepseek.com/v1"
    )
  end

  def generate_script(news_content, date = Date.current)
    system_prompt = <<~PROMPT
      You are a professional crypto KOL (Key Opinion Leader) with 5+ years of experience.
      Your expertise covers:
      - Cryptocurrency markets (Bitcoin, Ethereum, Altcoins)
      - Global financial markets (Gold, Stocks, Forex)
      - Macroeconomic trends and their impact on crypto
      
      Your daily task: Create a 150-word English video script based on today's crypto/financial news.
      
      Requirements:
      1. Provide objective analysis, NOT investment advice
      2. Focus on factual reporting and market trends
      3. Maintain professional yet accessible tone
      4. Include specific data/numbers when available
      5. End with a thought-provoking question or forward-looking statement
      6. Perfect for 60-second video delivery
      7. Use simple, clear English suitable for non-native speakers
      
      Script Structure:
      - Hook (first 15 words): Catch attention
      - Main analysis (100 words): Key insights
      - Conclusion (35 words): Wrap-up and future outlook
    PROMPT

    user_prompt = <<~USER
      Today is #{date.strftime("%B %d, %Y")}.
      
      Here are the latest crypto and financial news updates:
      
      #{news_content}
      
      Please generate a 150-word English video script based on this information.
      Make it timely, insightful, and suitable for a daily crypto news video.
      
      Format the output as a clean script with no markdown or special characters.
    USER

    begin
      response = @client.chat(
        parameters: {
          model: "deepseek-chat",
          messages: [
            { role: "system", content: system_prompt },
            { role: "user", content: user_prompt }
          ],
          temperature: 0.7,
          max_tokens: 400,
          top_p: 0.9
        }
      )

      response.dig("choices", 0, "message", "content").strip
    rescue => e
      Rails.logger.error "DeepSeek API Error: #{e.message}"
      nil
    end
  end

  # 生成多版本脚本（用于A/B测试）
  def generate_variants(news_content, count = 3)
    variants = []
    count.times do |i|
      variant = generate_script(news_content)
      variants << variant if variant.present?
    end
    variants.uniq
  end
end