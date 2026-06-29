# crypto_daily_script.rb
require "net/http"
require "json"
require "date"

class CryptoDailyScript
  def initialize(api_key)
    @api_key = ENV['DEEPSEEK_API_KEY']
    @uri = URI("https://api.deepseek.com/v1/chat/completions")
  end

  def generate
    puts "🚀 Generating daily crypto script..."
    puts "📅 Date: #{Date.today.strftime('%Y-%m-%d')}"
    
    # 1. 获取新闻
    news = fetch_crypto_news
    
    # 2. 生成脚本
    script = generate_script(news)
    
    # 3. 保存和输出
    if script
      save_and_display(script)
    else
      puts "❌ Generation failed"
    end
    
    script
  end

  private

  def fetch_crypto_news
    # 方案A: 从RSS获取（可选）
    # 方案B: 使用硬编码新闻（当前使用）
    <<~NEWS
      • Bitcoin (BTC) trades at $67,200, up 3.5% in 24 hours
      • Ethereum (ETH) holds above $3,500 with network upgrade planned
      • Gold reaches new high of $2,100 per ounce
      • Federal Reserve signals potential rate cuts in 2026
      • Solana ecosystem grows 40% in Q1 2026
      • Total crypto market cap: $2.9 trillion
      • Institutional inflows reach $500 million daily
      • Regulatory developments in EU and Asia markets
    NEWS
  end

  def generate_script(news)
    system_prompt = <<~SYSTEM
      You are a professional crypto KOL (Key Opinion Leader) with expertise in:
      - Cryptocurrency markets and blockchain technology
      - Global financial markets including gold and stocks
      - Macroeconomic trends
      
      Your task: Create a 150-word English video script for a daily crypto news update.
      
      CRITICAL RULES:
      1. Provide objective analysis, NEVER give investment advice
      2. Include specific numbers and data points
      3. Use conversational, clear English
      4. End with a forward-looking question or insight
      5. Perfect for a 60-second video delivery
      6. DO NOT use markdown, bullet points, or special formatting
      7. Just plain text script only
    SYSTEM

    user_prompt = <<~USER
      Today is #{Date.today.strftime('%B %d, %Y')}.
      
      Latest crypto and financial market news:
      #{news}
      
      Generate a 150-word English video script based on this news.
      Focus on the most important developments and their market implications.
      Keep it educational and factual.
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

    puts "⏳ Calling DeepSeek API..."

    response = http.request(request)
    
    if response.code == "200"
      result = JSON.parse(response.body)
      script = result.dig("choices", 0, "message", "content")
      puts "✅ Script generated successfully!"
      script
    else
      error_body = JSON.parse(response.body) rescue {"error" => {"message" => "Unknown"}}
      puts "❌ API Error (#{response.code}): #{error_body.dig('error', 'message')}"
      puts "Full response: #{response.body[0..200]}..."
      nil
    end
  rescue Timeout::Error
    puts "❌ Timeout: API took too long to respond"
    nil
  rescue => e
    puts "❌ Unexpected error: #{e.message}"
    puts e.backtrace.first(3)
    nil
  end

  def save_and_display(script)
    word_count = script.split.length
    
    # 显示
    puts "\n" + "=" * 70
    puts "📊 DAILY CRYPTO SCRIPT"
    puts "📅 #{Date.today.strftime('%B %d, %Y')}"
    puts "=" * 70
    puts script
    puts "=" * 70
    puts "📊 Word Count: #{word_count} / 150"
    puts "📝 Characters: #{script.length}"
    puts "=" * 70
    
    # 保存
    filename = "crypto_script_#{Date.today.strftime('%Y%m%d')}.txt"
    File.write(filename, script)
    puts "💾 Saved to: #{filename}"
    
    # 同时保存带元数据的版本
    metadata_filename = "crypto_script_#{Date.today.strftime('%Y%m%d')}_with_meta.txt"
    File.write(metadata_filename, <<~META)
      DATE: #{Date.today.strftime('%B %d, %Y')}
      WORD COUNT: #{word_count}
      CHARACTERS: #{script.length}
      GENERATED AT: #{Time.now}
      #{'-' * 50}
      #{script}
    META
    puts "💾 Full version saved to: #{metadata_filename}"
  end
end
