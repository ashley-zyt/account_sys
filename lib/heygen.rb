require 'httparty'
require 'json'

class Heygen
  class << self
    def run_crypto_video_pipeline
      crypto_data = fetch_crypto_data
      return unless crypto_data.present?

      Rails.logger.info "[Heygen] 已获取到加密货币数据"

      content = generate_content(crypto_data)
      return unless content.present?
      Rails.logger.info "[Heygen] 生成内容: #{content}"
      
      Rails.logger.info "[Heygen] 生成内容成功"

      create_video(content, crypto_data)
    end

    def fetch_crypto_data
      Rails.logger.info "[Heygen] 开始获取加密货币数据"

      data = {
        global_crypto: fetch_global_crypto,
        global_defi: fetch_global_defi,
        trending: fetch_trending
      }

      Rails.logger.info "[Heygen] 获取加密货币数据完成"
      data
    rescue => e
      Rails.logger.error "[Heygen] 获取加密货币数据失败: #{e.message}"
      nil
    end

    def fetch_global_crypto
      url = 'https://api.coingecko.com/api/v3/global'
      response = HTTParty.get(url, headers: coingecko_headers, timeout: 30)
      response.parsed_response
    rescue HTTParty::Error, JSON::ParserError => e
      Rails.logger.error "[Heygen] 获取全球市场数据失败: #{e.message}"
      {}
    end

    def fetch_global_defi
      url = 'https://api.coingecko.com/api/v3/global/decentralized_finance_defi'
      response = HTTParty.get(url, headers: coingecko_headers, timeout: 30)
      response.parsed_response
    rescue HTTParty::Error, JSON::ParserError => e
      Rails.logger.error "[Heygen] 获取 DeFi 数据失败: #{e.message}"
      {}
    end

    def fetch_trending
      url = 'https://api.coingecko.com/api/v3/search/trending'
      response = HTTParty.get(url, headers: coingecko_headers, timeout: 30)
      response.parsed_response
    rescue HTTParty::Error, JSON::ParserError => e
      Rails.logger.error "[Heygen] 获取热门搜索失败: #{e.message}"
      []
    end

    def coingecko_headers
      headers = {}
      api_key = ENV['COINGECKO_KEY']
      headers['x-cg-demo-api-key'] = api_key if api_key.present?
      headers
    end

    def generate_content(crypto_data)
      Rails.logger.info "[Heygen] 开始生成内容"

      prompt = build_prompt(crypto_data)
      response = call_deepseek_api(prompt)
      return nil unless response.present?

      parsed = parse_deepseek_response(response)
      return nil unless parsed.present?

      {
        video_text: parsed['video_text'],
        title: build_full_title(parsed),
        description: parsed['description'],
        hashtags: parsed['hashtags'] || [],
        theme: parsed['theme'] || '加密货币',
        prompt: prompt
      }
    rescue => e
      Rails.logger.error "[Heygen] 生成内容失败: #{e.message}"
      nil
    end

    def build_prompt(crypto_data)
      global = crypto_data[:global_crypto]
      defi = crypto_data[:global_defi]
      trending = crypto_data[:trending]

      trending_coins = trending['coins'] || []
      top_trending = trending_coins.first(3).map { |c| "#{c['item']['name']} (#{c['item']['symbol']})" }.join(', ')

      <<~PROMPT
        这是今日的 CoinGecko 数据，请生成今日 Global Crypto Brief（英文口播稿、社媒标题、文案、热词）

        全球市场概览：
        - 总市值：$#{format_number(global.dig('data', 'total_market_cap', 'usd'))}
        - 24小时交易量：$#{format_number(global.dig('data', 'total_volume', 'usd'))}
        - BTC 占比：#{global.dig('data', 'market_cap_percentage', 'btc')}%
        - ETH 占比：#{global.dig('data', 'market_cap_percentage', 'eth')}%

        DeFi 数据：
        - DeFi 总锁仓量：$#{format_number(defi.dig('defi_market_cap', 'usd'))}
        - DeFi 交易量：$#{format_number(defi.dig('trading_volume_24h', 'usd'))}

        热门搜索：#{top_trending}

        请输出JSON格式，包含以下字段：
        - video_text: 英文口播逐字稿，约150字，开头必须是"Hello and welcome to Global Crypto Brief."，口语化，适合短视频口播，包含一两句趋势研判
        - title: 社媒标题，不超过100字母，吸引眼球，包含关键词，符合海外社媒风格
        - description: 社媒文案，不超过150字母，精简提炼，包含趋势研判，吸引关注获取流量
        - hashtags: 热词数组，5-8个相关话题，带#号，吸引流量
        - theme: 内容主题，用于分类

        注意：只输出JSON，不要包含其他内容。
      PROMPT
    end

    def call_deepseek_api(prompt)
      api_key = ENV['DEEPSEEK_API_KEY']
      return nil unless api_key.present?

      body = {
        model: 'deepseek-chat',
        messages: [
          { role: 'system', content: 'You are a professional crypto content creator specializing in Global Crypto Brief. You excel at writing engaging short video scripts and social media posts in English. Your outputs should be concise, attention-grabbing, and optimized for overseas social media platforms.' },
          { role: 'user', content: prompt }
        ],
        temperature: 0.7,
        max_tokens: 1000
      }

      response = HTTParty.post(
        'https://api.deepseek.com/v1/chat/completions',
        headers: {
          'Content-Type' => 'application/json',
          'Authorization' => "Bearer #{api_key}"
        },
        body: body.to_json,
        timeout: 60
      )

      return nil unless response.success?

      response.parsed_response
    rescue HTTParty::Error, JSON::ParserError => e
      Rails.logger.error "[Heygen] DeepSeek API 请求错误: #{e.message}"
      nil
    end

    def parse_deepseek_response(response)
      content = response.dig('choices', 0, 'message', 'content')
      return nil unless content.present?

      JSON.parse(content)
    rescue JSON::ParserError
      Rails.logger.error "[Heygen] JSON 解析失败: #{content}"
      nil
    end

    def build_full_title(parsed)
      title = parsed['title'] || ''
      hashtags = (parsed['hashtags'] || []).join(' ')
      hashtags.present? ? "#{title} #{hashtags}" : title
    end

    def create_video(content, crypto_data)
      # 获取模板变量
      # curl -X GET "https://api.heygen.com/v2/template/template_id" -H "X-Api-Key: key"
      Rails.logger.info "[Heygen] 开始创建视频"

      crypto_video = CryptoVideo.create!(
        global_crypto: crypto_data[:global_crypto].to_json,
        global_defi: crypto_data[:global_defi].to_json,
        trending: crypto_data[:trending].to_json,
        prompt: content[:prompt],
        video_status: '生成中'
      )

      video_id = generate_video(content[:video_text])
      return nil unless video_id.present?

      crypto_video.update!(video_id: video_id)

      heygen_task = HeygenTask.create!(
        theme: content[:theme],
        video_text: content[:video_text],
        title: content[:title],
        description: content[:description],
        templete_id: video_id,
        status: :executing,
        start_at: Time.current,
        video_status: '生成中'
      )

      Rails.logger.info "[Heygen] 创建视频成功: crypto_video_id=#{crypto_video.id} heygen_task_id=#{heygen_task.id} video_id=#{video_id}"

      { crypto_video: crypto_video, heygen_task: heygen_task }
    rescue => e
      Rails.logger.error "[Heygen] 创建视频失败: #{e.message}"
      nil
    end

    def generate_video(video_text)
      api_key = ENV['HEYGEN_API_KEY']
      return nil unless api_key.present?

      template_id = get_template_id

      body = {
        title: "Global Crypto Brief",
        caption: true,
        dimension: {
          width: 1080,
          height: 1920
        },
        keep_text_vertically_centered: true,
        variables: {
          script: {
            name: 'script',
            type: 'text',
            properties: {
              content: video_text
            }
          }
        }
      }

      response = HTTParty.post(
        "https://api.heygen.com/v2/template/#{template_id}/generate",
        headers: {
          'Content-Type' => 'application/json',
          'X-Api-Key' => api_key
        },
        body: body.to_json,
        timeout: 60
      )

      return nil unless response.success?

      parsed_response = response.parsed_response
      video_id = parsed_response.dig('data', 'video_id')

      if video_id.present?
        Rails.logger.info "[Heygen] 视频生成接口调用成功: video_id=#{video_id}"
        video_id
      else
        Rails.logger.error "[Heygen] 视频生成接口调用失败: video_id 获取不到，响应: #{parsed_response}"
        nil
      end
    rescue HTTParty::Error, JSON::ParserError => e
      Rails.logger.error "[Heygen] 调用视频生成接口失败: #{e.message}"
      nil
    end

    def get_template_id
      '64d574f45d3e43688afb8dcd6cbc99e4'
    end

    def fetch_video_info(video_id)
      api_key = ENV['HEYGEN_API_KEY']
      return nil unless api_key.present?

      response = HTTParty.get(
        "https://api.heygen.com/v3/videos/#{video_id}",
        headers: { 'X-Api-Key' => api_key },
        timeout: 30
      )

      return nil unless response.success?

      response.parsed_response['data']
    rescue HTTParty::Error, JSON::ParserError => e
      Rails.logger.error "[Heygen] 获取视频信息失败: #{e.message}"
      nil
    end


    def format_number(number)
      return '0' unless number.present?

      if number >= 1_000_000_000
        "#{(number / 1_000_000_000).round(2)}B"
      elsif number >= 1_000_000
        "#{(number / 1_000_000).round(2)}M"
      elsif number >= 1_000
        "#{(number / 1_000).round(2)}K"
      else
        number.to_s
      end
    end
  end
end