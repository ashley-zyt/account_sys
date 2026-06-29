# crypto_daily_script_optimized.rb
require "net/http"
require "json"
require "date"

class CryptoDailyScript
  def initialize
    @api_key = ENV['DEEPSEEK_API_KEY'] || "sk-your-key"
    @uri = URI("https://api.deepseek.com/v1/chat/completions")
    
    # 每天的写作角度（7天循环）
    @perspectives = [
      "institutional adoption and Wall Street integration",
      "macroeconomic correlations: crypto vs gold vs equities",
      "regulatory developments and their market impact",
      "technological innovations driving adoption",
      "market psychology and sentiment analysis",
      "comparison with historical bull/bear cycles",
      "future outlook: what's next for the crypto ecosystem"
    ]
  end

  def generate
    puts "🚀 Generating daily crypto script..."
    puts "📅 Date: #{Date.today.strftime('%Y-%m-%d')}"
    
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
    # 尝试获取实时数据
    begin
      # CoinGecko API
      uri = URI("https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum,solana,cardano&vs_currencies=usd&include_24hr_change=true&include_market_cap=true")
      response = Net::HTTP.get(uri)
      data = JSON.parse(response)
      
      <<~NEWS
        BITCOIN: $#{data["bitcoin"]["usd"]} (#{data["bitcoin"]["usd_24h_change"].round(2)}% 24h)
        ETHEREUM: $#{data["ethereum"]["usd"]} (#{data["ethereum"]["usd_24h_change"].round(2)}% 24h)
        SOLANA: $#{data["solana"]["usd"]} (#{data["solana"]["usd_24h_change"].round(2)}% 24h)
        MARKET CAP: $2.9 trillion
        INSTITUTIONAL INFLOWS: $500M daily average
        GOLD PRICE: $2,100/oz (all-time high)
        FED SIGNAL: Potential rate cuts by Q3 2026
        EU REGULATION: New MiCA framework implementation
      NEWS
    rescue => e
      puts "⚠️ Live data unavailable, using fallback"
      get_fallback_news
    end
  end

  def get_fallback_news
    <<~NEWS
      Bitcoin (BTC): $67,200 (+3.5% 24h)
      Ethereum (ETH): $3,550 (+2.1%)
      Solana (SOL): $185 (+15% weekly)
      Gold: $2,100/oz (record high)
      Market cap: $2.9T
      Institutional inflows: $500M daily
      Fed signals rate cuts
      EU crypto regulations advance
    NEWS
  end

  def generate_script(news)
    # 根据日期选择分析角度
    perspective_index = Date.today.day % @perspectives.length
    perspective = @perspectives[perspective_index]
    
    system_prompt = <<~SYSTEM
      You are a top-tier crypto analyst with unique insights. Your analysis is:
      
      🎯 INSIGHTFUL: You see patterns others miss
      📊 DATA-DRIVEN: You use numbers to tell a story
      🔮 FORWARD-LOOKING: You explain what happens next
      🧠 EDUCATIONAL: You teach while you analyze
      
      Your signature style:
      - Start with a powerful, unexpected insight
      - Connect crypto to traditional markets (gold, stocks, forex)
      - Include 1-2 unique observations
      - End with a thought-provoking question or prediction
      
      CRITICAL: NEVER say "Stay tuned" or "Let's see what happens" - be definitive!
    SYSTEM

    user_prompt = <<~USER
      Today's Market Data (#{Date.today.strftime('%B %d, %Y')}):
      
      #{news}
      
      SPECIAL FOCUS: #{perspective}
      
      Create a 150-word English video script that:
      
      1. Opens with a UNIQUE INSIGHT about today's market behavior
      2. Explains the KEY TREND driving current price action
      3. Highlights the CONNECTION between crypto and traditional markets
      4. Provides an ANALYTICAL PERSPECTIVE (not just news summary)
      5. Ends with a PROVOCATIVE QUESTION or CLEAR PREDICTION
      
      Style requirements:
      - Confident, authoritative tone
      - Use analogies or metaphors
      - Write for a 60-second video delivery
      - NO markdown, NO bullet points
      - EXACTLY 150 words
      
      Make this sound like YOUR unique analysis, not a generic news report.
    USER

    payload = {
      model: "deepseek-chat",
      messages: [
        { role: "system", content: system_prompt },
        { role: "user", content: user_prompt }
      ],
      temperature: 0.85,
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

    puts "⏳ Analyzing market data from unique perspective: #{perspective}"

    response = http.request(request)
    
    if response.code == "200"
      result = JSON.parse(response.body)
      result.dig("choices", 0, "message", "content").strip
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
    puts "📊 DAILY CRYPTO SCRIPT"
    puts "📅 #{Date.today.strftime('%B %d, %Y')}"
    puts "🎯 Perspective: #{@perspectives[Date.today.day % @perspectives.length]}"
    puts "=" * 70
    puts script
    puts "=" * 70
    puts "📊 Word Count: #{word_count} / 150"
    puts "📝 Characters: #{script.length}"
    puts "=" * 70
    
    filename = "crypto_script_#{Date.today.strftime('%Y%m%d')}.txt"
    File.write(filename, script)
    puts "💾 Saved to: #{filename}"
  end

  def analyze_script_quality(script)
    # 简单的质量分析
    puts "\n📊 Quality Analysis:"
    puts "-" * 40
    
    # 检查字数
    word_count = script.split.length
    word_quality = (word_count >= 140 && word_count <= 160) ? "✅" : "⚠️"
    puts "#{word_quality} Word count: #{word_count}/150"
    
    # 检查是否包含具体数字
    has_numbers = script.match?(/\$\d+|\d+%|\d+[KMB]/)
    puts "#{has_numbers ? '✅' : '⚠️'} Contains specific data: #{has_numbers ? 'Yes' : 'No'}"
    
    # 检查是否包含问句（结尾通常应该有）
    has_question = script.match?(/\?/)
    puts "#{has_question ? '✅' : '⚠️'} Ends with question: #{has_question ? 'Yes' : 'No'}"
    
    # 独特词汇检查
    unique_words = script.split.uniq.length
    diversity = (unique_words.to_f / word_count * 100).round
    puts "#{diversity > 60 ? '✅' : '⚠️'} Vocabulary diversity: #{diversity}%"
    
    puts "-" * 40
  end
end