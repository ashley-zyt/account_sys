# crypto_daily_script_host.rb
require "net/http"
require "json"
require "date"

class CryptoDailyScript
  def initialize
    @api_key = ENV['DEEPSEEK_API_KEY']
    @uri = URI("https://api.deepseek.com/v1/chat/completions")
    
    # 主持人名字（可自定义）
    @host_name = "Alex"
    
    # 每日不同的话题角度（保持内容多样性）
    @perspectives = [
      "market momentum and price action",
      "institutional adoption trends",
      "macroeconomic factors affecting crypto",
      "regulatory updates worldwide",
      "technology and innovation highlights",
      "market sentiment and psychology",
      "global adoption and real-world use cases"
    ]
  end

  def generate
    puts "🚀 Generating daily crypto script for digital human host..."
    puts "📅 Date: #{Date.today.strftime('%Y-%m-%d')}"
    puts "🎙️  Host: #{@host_name}"
    
    news = fetch_crypto_news
    script = generate_script(news)
    
    if script
      save_and_display(script)
      analyze_script_quality(script)
    end
    
    script
  end

  private

  def fetch_crypto_news
    begin
      # CoinGecko实时数据
      uri = URI("https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum,solana,cardano,ripple&vs_currencies=usd&include_24hr_change=true&include_market_cap=true")
      response = Net::HTTP.get(uri)
      data = JSON.parse(response)
      
      # 尝试获取新闻（备用）
      news_headlines = fetch_news_headlines
      
      <<~NEWS
        PRICE DATA:
        Bitcoin: $#{data["bitcoin"]["usd"]} (#{data["bitcoin"]["usd_24h_change"].round(2)}% 24h)
        Ethereum: $#{data["ethereum"]["usd"]} (#{data["ethereum"]["usd_24h_change"].round(2)}% 24h)
        Solana: $#{data["solana"]["usd"]} (#{data["solana"]["usd_24h_change"].round(2)}% 24h)
        
        MARKET OVERVIEW:
        Total Market Cap: $2.9 trillion
        24h Volume: $85 billion
        BTC Dominance: 52.3%
        
        MACRO NEWS:
        Gold: $2,100/oz
        Fed Rate Cut Signals: Expected Q3 2026
        US Dollar Index: 103.5
        
        TOP HEADLINES:
        #{news_headlines}
      NEWS
    rescue => e
      puts "⚠️ Live data unavailable, using fallback"
      get_fallback_news
    end
  end

  def fetch_news_headlines
    # 尝试从RSS获取最新标题
    headlines = []
    sources = [
      "https://cointelegraph.com/rss",
      "https://decrypt.co/feed"
    ]
    
    sources.each do |url|
      begin
        uri = URI(url)
        response = Net::HTTP.get(uri)
        feed = RSS::Parser.parse(response, false)
        feed.items.first(2).each do |item|
          headlines << "- #{item.title}"
        end
      rescue
        # 静默失败
      end
    end
    
    headlines.empty? ? "Crypto markets show mixed signals today" : headlines.join("\n")
  rescue
    "Crypto markets show mixed signals today"
  end

  def get_fallback_news
    <<~NEWS
      Bitcoin: $67,200 (+3.5%)
      Ethereum: $3,550 (+2.1%)
      Solana: $185 (+15% weekly)
      Market Cap: $2.9T
      Gold: $2,100/oz (record high)
      Fed signals rate cuts
      Institutional inflows: $500M daily
    NEWS
  end

  def generate_script(news)
    perspective_index = Date.today.day % @perspectives.length
    perspective = @perspectives[perspective_index]
    
    # ⭐ 核心优化：主持人风格System Prompt
    system_prompt = <<~SYSTEM
      You are a professional crypto news HOST for a daily video show.
      Your style is:
      
      🎙️ CONVERSATIONAL: Sound like you're talking directly to viewers
      🎙️ ENGAGING: Use natural speaking rhythms and pauses
      🎙️ CLEAR: Simple sentences that are easy to voice-over
      🎙️ WARM: Friendly and approachable, not robotic
      🎙️ PROFESSIONAL: Knowledgeable but not technical-jargon heavy
      
      Your show format:
      - Opening: Greet viewers and state the date
      - Main segment: Top 2-3 crypto/market stories
      - Insight: Your brief take on what it means
      - Closing: Wrap up and invite viewers back
      
      CRITICAL RULES:
      1. Write for SPEAKING, not reading - use conversational English
      2. Include natural pauses (commas, periods for breathing)
      3. NEVER say "Stay tuned" - use personal sign-off instead
      4. Address viewers as "you" - create connection
      5. Keep sentences short (max 15-20 words)
      6. Include 1 rhetorical question to engage viewers
      7. EXACTLY 150 words
      8. NO markdown, NO bullet points
      
      You are the host #{@host_name}. Sign off with "I'm #{@host_name}, see you tomorrow."
    SYSTEM

    user_prompt = <<~USER
      Today is #{Date.today.strftime('%A, %B %d, %Y')}.
      
      Market Data:
      #{news}
      
      Today's Focus: #{perspective}
      
      Create a 150-word ENGLISH VIDEO SCRIPT for a digital human host.
      
      The script should sound like a professional news anchor speaking directly to the camera.
      Imagine you're recording a 60-second YouTube Short or TikTok video.
      
      Use:
      - Greeting: "Good morning everyone" or "Welcome back"
      - Active voice: "Bitcoin is surging..." not "Bitcoin has been seen surging..."
      - Personal touch: "Let's break down what this means for you"
      - Clear transitions: "Now let's talk about..." "Meanwhile..."
      - Engaging questions: "So what's driving this move?"
      - Professional sign-off: "I'm #{@host_name}, see you tomorrow"
      
      Remember: This is for a VIDEO, so make it SPOKEN and NATURAL.
    USER

    payload = {
      model: "deepseek-chat",
      messages: [
        { role: "system", content: system_prompt },
        { role: "user", content: user_prompt }
      ],
      temperature: 0.8,
      max_tokens: 450,
      top_p: 0.95
    }

    http = Net::HTTP.new(@uri.host, @uri.port)
    http.use_ssl = true
    http.read_timeout = 30

    request = Net::HTTP::Post.new(@uri)
    request["Content-Type"] = "application/json"
    request["Authorization"] = "Bearer #{@api_key}"
    request.body = payload.to_json

    puts "⏳ Generating host-style script..."

    response = http.request(request)
    
    if response.code == "200"
      result = JSON.parse(response.body)
      script = result.dig("choices", 0, "message", "content").strip
      
      # 后处理：确保有主持人签名
      unless script.include?("I'm #{@host_name}")
        script += " I'm #{@host_name}, see you tomorrow."
      end
      
      script
    else
      error = JSON.parse(response.body) rescue {"error" => {"message" => "Unknown"}}
      puts "❌ API Error: #{error.dig('error', 'message')}"
      nil
    end
  rescue => e
    puts "❌ Error: #{e.message}"
    nil
  end

  def save_and_display(script)
    word_count = script.split.length
    
    puts "\n" + "=" * 70
    puts "🎙️  DAILY CRYPTO SCRIPT - HOST VERSION"
    puts "📅 #{Date.today.strftime('%A, %B %d, %Y')}"
    puts "🎯 Focus: #{@perspectives[Date.today.day % @perspectives.length]}"
    puts "=" * 70
    puts script
    puts "=" * 70
    puts "📊 Word Count: #{word_count} / 150"
    puts "⏱️  Estimated Speaking Time: #{(word_count / 2.5).round} seconds"
    puts "=" * 70
    
    # 保存文件
    filename = "host_script_#{Date.today.strftime('%Y%m%d')}.txt"
    File.write(filename, script)
    puts "💾 Saved to: #{filename}"
    
    # 同时生成配音专用版（带停顿标记）
    voiceover_filename = "voiceover_#{Date.today.strftime('%Y%m%d')}.txt"
    voiceover_script = add_speaking_guidance(script)
    File.write(voiceover_filename, voiceover_script)
    puts "💾 Voiceover version saved to: #{voiceover_filename}"
  end

  def add_speaking_guidance(script)
    # 为配音添加指导标记（可选）
    <<~GUIDE
      SPEAKING GUIDE - Read at moderate pace
      ----------------------------------------
      
      • Pause briefly at periods (.)
      • Pause slightly at commas (,)
      • Emphasize numbers and percentages
      • Smile when greeting viewers
      • Use hand gestures for emphasis
      
      SCRIPT:
      #{script}
      
      TIMING: ~60 seconds at normal speaking pace
    GUIDE
  end

  def analyze_script_quality(script)
    puts "\n📊 Quality Analysis:"
    puts "-" * 40
    
    word_count = script.split.length
    puts "✅ Word count: #{word_count}/150"
    
    # 检查主持人风格特征
    has_greeting = script.match?(/Good morning|Welcome|Hello|Hey there/i)
    puts "#{has_greeting ? '✅' : '⚠️'} Has greeting: #{has_greeting ? 'Yes' : 'No'}"
    
    has_signoff = script.match?(/see you|tomorrow|I'm|that's all/i)
    puts "#{has_signoff ? '✅' : '⚠️'} Has sign-off: #{has_signoff ? 'Yes' : 'No'}"
    
    has_question = script.match?(/\?/)
    puts "#{has_question ? '✅' : '⚠️'} Has engaging question: #{has_question ? 'Yes' : 'No'}"
    
    # 检查口语化程度（简单句比例）
    sentences = script.split(/[.!?]+/).map(&:strip).reject(&:empty?)
    avg_words = sentences.map { |s| s.split.length }.sum / sentences.length.to_f
    conversational = avg_words < 15
    puts "#{conversational ? '✅' : '⚠️'} Conversational style: #{avg_words.round(1)} words/sentence (#{conversational ? 'Good' : 'Too long'})"
    
    puts "-" * 40
  end
end