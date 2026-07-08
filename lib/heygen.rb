require 'httparty'
require 'json'

class Heygen
  class << self
    def run_crypto_video_pipeline
      crypto_data = fetch_crypto_data
      return unless crypto_data.present?

      Rails.logger.info "[Heygen] 已获取到加密货币数据"

      template_ids = get_template_ids
      return if template_ids.empty?

      Rails.logger.info "[Heygen] 共获取到 #{template_ids.size} 个模板: #{template_ids.map { |t| "#{t[:theme_name]}=#{t[:template_id]}" }.join(', ')}"

      template_ids.each do |template_info|
        theme_name = template_info[:theme_name]
        template_id = template_info[:template_id]

        Rails.logger.info "[Heygen] 开始处理主题: #{theme_name}, 模板: #{template_id}"

        content = generate_content(crypto_data, theme_name)
        next unless content.present?

        Rails.logger.info "[Heygen] 主题 #{theme_name} 生成内容成功"

        create_video(content, crypto_data, template_id)
      end
    end

    def fetch_crypto_data
      Rails.logger.info "[Heygen] 开始获取加密货币数据"

      data = {
        global_crypto: fetch_global_crypto,
        global_defi: fetch_global_defi,
        trending: fetch_trending,
        top_coins: fetch_top_coins,
        nft_data: fetch_nft_data,
        market_sentiment: fetch_market_sentiment
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

    def fetch_top_coins
      url = 'https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&order=market_cap_desc&per_page=10&page=1&sparkline=false&price_change_percentage=24h'
      response = HTTParty.get(url, headers: coingecko_headers, timeout: 30)
      response.parsed_response
    rescue HTTParty::Error, JSON::ParserError => e
      Rails.logger.error "[Heygen] 获取主流币种数据失败: #{e.message}"
      []
    end

    def fetch_nft_data
      url = 'https://api.coingecko.com/api/v3/nfts/list?order=h24_volume_usd_desc&per_page=5'
      response = HTTParty.get(url, headers: coingecko_headers, timeout: 30)
      response.parsed_response
    rescue HTTParty::Error, JSON::ParserError => e
      Rails.logger.error "[Heygen] 获取 NFT 数据失败: #{e.message}"
      []
    end

    def fetch_market_sentiment
      url = 'https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&ids=bitcoin,ethereum&sparkline=false&price_change_percentage=24h,7d,30d'
      response = HTTParty.get(url, headers: coingecko_headers, timeout: 30)
      response.parsed_response
    rescue HTTParty::Error, JSON::ParserError => e
      Rails.logger.error "[Heygen] 获取市场情绪数据失败: #{e.message}"
      []
    end

    def coingecko_headers
      headers = {}
      api_key = ENV['COINGECKO_KEY']
      headers['x-cg-demo-api-key'] = api_key if api_key.present?
      headers
    end

    def generate_content(crypto_data, theme_name)
      Rails.logger.info "[Heygen] 开始生成内容: theme=#{theme_name}"

      prompt = build_prompt(crypto_data, theme_name)
      response = call_deepseek_api(prompt)
      return nil unless response.present?

      parsed = parse_deepseek_response(response)
      return nil unless parsed.present?

      {
        video_text: parsed['video_text'],
        title: build_full_title(parsed),
        description: parsed['description'],
        hashtags: parsed['hashtags'] || [],
        theme: theme_name,
        prompt: prompt
      }
    rescue => e
      Rails.logger.error "[Heygen] 生成内容失败: #{e.message}"
      nil
    end

    def build_prompt(crypto_data, theme_name)
      global = crypto_data[:global_crypto]
      defi = crypto_data[:global_defi]
      trending = crypto_data[:trending]
      top_coins = crypto_data[:top_coins] || []
      nft_data = crypto_data[:nft_data] || []
      market_sentiment = crypto_data[:market_sentiment] || []

      trending_coins = trending['coins'] || []
      top_trending = trending_coins.first(3).map { |c| "#{c['item']['name']} (#{c['item']['symbol']})" }.join(', ')

      top_coins_info = top_coins.first(5).map do |coin|
        change = coin['price_change_percentage_24h']
        direction = change.to_f >= 0 ? '📈' : '📉'
        "#{direction} #{coin['name']} (#{coin['symbol']}): $#{format_number(coin['current_price'])} (#{change.to_f.round(2)}%)"
      end.join("\n")

      nft_info = nft_data.first(3).map do |nft|
        "🎨 #{nft['name']}: #{nft['h24_volume_usd'] ? "$#{format_number(nft['h24_volume_usd'])}" : '数据未更新'}"
      end.join("\n")

      btc_sentiment = market_sentiment.find { |c| c['id'] == 'bitcoin' }
      eth_sentiment = market_sentiment.find { |c| c['id'] == 'ethereum' }
      sentiment_info = []
      sentiment_info << "📊 BTC 24h: #{btc_sentiment['price_change_percentage_24h'].to_f.round(2)}%, 7d: #{btc_sentiment['price_change_percentage_7d'].to_f.round(2)}%" if btc_sentiment
      sentiment_info << "📊 ETH 24h: #{eth_sentiment['price_change_percentage_24h'].to_f.round(2)}%, 7d: #{eth_sentiment['price_change_percentage_7d'].to_f.round(2)}%" if eth_sentiment

      content_angles = [
        "市场热点追踪",
        "主流币种分析",
        "DeFi 生态动态",
        "NFT 市场观察",
        "投资趋势研判",
        "加密货币新闻速览"
      ]
      content_angle = content_angles.sample

      opening_lines = [
        "Hello and welcome to Global Crypto Brief."
      ]
      opening_line = opening_lines.sample

      <<~PROMPT
        这是今日的 CoinGecko 数据，请生成今日 #{theme_name}（英文口播稿、社媒标题、文案、热词）

        内容角度：#{content_angle}

        全球市场概览：
        - 总市值：$#{format_number(global.dig('data', 'total_market_cap', 'usd'))}
        - 24小时交易量：$#{format_number(global.dig('data', 'total_volume', 'usd'))}
        - BTC 占比：#{global.dig('data', 'market_cap_percentage', 'btc')}%
        - ETH 占比：#{global.dig('data', 'market_cap_percentage', 'eth')}%

        DeFi 数据：
        - DeFi 总锁仓量：$#{format_number(defi.dig('defi_market_cap', 'usd'))}
        - DeFi 交易量：$#{format_number(defi.dig('trading_volume_24h', 'usd'))}

        主流币种行情：
        #{top_coins_info}

        市场情绪指标：
        #{sentiment_info.join("\n")}

        NFT 热门项目：
        #{nft_info}

        热门搜索：#{top_trending}

        请输出JSON格式，包含以下字段：
        - video_text: 英文口播逐字稿，约150字，开头必须是"#{opening_line}"，口语化，适合短视频口播，根据#{content_angle}角度深度分析，包含趋势研判和投资建议
        - title: 社媒标题，不超过100字母，吸引眼球，包含关键词，符合海外社媒风格，使用 emoji 增强吸引力
        - description: 社媒文案，不超过80字母，精简提炼，包含趋势研判，吸引关注获取流量
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

    def create_video(content, crypto_data, template_id)
      Rails.logger.info "[Heygen] 开始创建视频: template_id=#{template_id}"

      crypto_video = CryptoVideo.create!(
        global_crypto: crypto_data[:global_crypto].to_json,
        global_defi: crypto_data[:global_defi].to_json,
        trending: crypto_data[:trending].to_json,
        prompt: content[:prompt],
        video_status: '生成中'
      )

      video_id = generate_video(content[:video_text], template_id)
      return nil unless video_id.present?

      

      heygen_task = HeygenTask.create!(
        theme: content[:theme],
        video_text: content[:video_text],
        title: content[:title],
        description: content[:description],
        templete_id: video_id,
        status: :pending,
        start_at: Time.current
      )
      crypto_video.update!(video_id: video_id,heygen_task_id:heygen_task.id)
      Rails.logger.info "[Heygen] 创建视频成功: crypto_video_id=#{crypto_video.id} heygen_task_id=#{heygen_task.id} video_id=#{video_id}"

      { crypto_video: crypto_video, heygen_task: heygen_task }
    rescue => e
      Rails.logger.error "[Heygen] 创建视频失败: #{e.message}"
      nil
    end

    def generate_video(video_text, template_id)
      api_key = ENV['HEYGEN_API_KEY']
      return nil unless api_key.present?
      return nil unless template_id.present?

      body = {
        title: "Agic Video",
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
        Rails.logger.info "[Heygen] 视频生成接口调用成功: template_id=#{template_id} video_id=#{video_id}"
        video_id
      else
        Rails.logger.error "[Heygen] 视频生成接口调用失败: video_id 获取不到，响应: #{parsed_response}"
        nil
      end
    rescue HTTParty::Error, JSON::ParserError => e
      Rails.logger.error "[Heygen] 调用视频生成接口失败: #{e.message}"
      nil
    end

    def get_template_ids
      heygen_themes = Account.where(work_type: 'Heygen', status: '正常').distinct.pluck(:theme).compact
      return [] if heygen_themes.empty?

      themes = Theme.where(name: heygen_themes).where.not(remark: nil)
      themes.map { |t| { theme_name: t.name, template_id: t.remark } }
    end

    def fetch_video_info
      api_key = ENV['HEYGEN_API_KEY']
      return nil unless api_key.present?
      crypto_videos = CryptoVideo.where(video_status:"生成中")
      crypto_videos.each do |video|
        response = HTTParty.get(
          "https://api.heygen.com/v3/videos/#{video.video_id}",
          headers: { 'X-Api-Key' => api_key },
          timeout: 30
        )
        caption_url = response.parsed_response['data']['captioned_video_url'] rescue nil
        if caption_url
          task = HeygenTask.find_by(id: video.heygen_task_id)
          next unless task.present?
          title,description = task['title'], task['description']
          
          platforms = %w[facebook twitter tiktok instagram]
          platforms.each do |platform|
            HeygenTask.create(
              theme: task['theme'],
              video_url: caption_url,
              status: 0,
              templete_id: task['templete_id'],
              video_text: task['video_text'],
              task_uuid: task['task_uuid'],
              platform: platform,
              title: title,
            )
          end
          task.update!(video_url: caption_url, platform: 'youtube',title:description,description: title)
          video.update!(video_status:"已完成")
        end
      end
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