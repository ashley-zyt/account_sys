# crypto_script_generator_advanced.rb
require "openai"
require "net/http"
require "json"
require "rss"
require "date"

class CryptoScriptGenerator
  def initialize
    # 修复：正确设置API Key
    access_key_id = ENV['DEEPSEEK_API_KEY']
    
    if access_key_id.nil? || access_key_id.empty?
      puts "⚠️  DEEPSEEK_API_KEY environment variable not set!"
      puts "Please set it with: export DEEPSEEK_API_KEY='your-key-here'"
      puts "Or hardcode it below (not recommended for production)"
      exit 1
    end
    
    # 两种初始化方式，任选一种
    @client = OpenAI::Client.new(
      access_token: access_key_id,
      uri_base: "https://api.deepseek.com/v1"
    )
    
    # 或者使用这种更简单的初始化
    # @client = OpenAI::Client.new(access_key_id)
  end

  def generate_today_script(manual_news = nil)
    # 如果手动传入新闻，直接使用；否则自动抓取
    news = manual_news || fetch_news_from_rss
    
    if news.empty?
      puts "⚠️  No news fetched, using fallback data"
      news = get_fallback_news
    end

    script = call_deepseek(news)
    
    # 输出和保存
    display_and_save(script, news)
    
    script
  rescue => e
    puts "❌ Error: #{e.message}"
    puts e.backtrace.first(5)
    nil
  end

  private

  def fetch_news_from_rss
    sources = [
      "https://cointelegraph.com/rss",
      "https://decrypt.co/feed",
      "https://news.bitcoin.com/feed/"
    ]
    
    all_news = []
    
    sources.each do |url|
      begin
        uri = URI(url)
        response = Net::HTTP.get(uri)
        feed = RSS::Parser.parse(response, false)
        
        feed.items.first(5).each do |item|
          all_news << "• #{item.title}"
          if item.description
            desc = item.description.gsub(/<[^>]*>/, '').strip
            all_news << "  #{desc}" if desc.length > 0
          end
        end
      rescue => e
        puts "⚠️  Failed to fetch #{url}: #{e.message}"
      end
    end
    
    all_news.join("\n")
  end

  def call_deepseek(news_content)
    prompt = <<~PROMPT
      Based on these crypto and financial news headlines:
      
      #{news_content}
      
      Create a 150-word English video script for a daily crypto update.
      
      Requirements:
      - Professional but accessible tone
      - Include key numbers and trends
      - No investment advice, just facts
      - End with a thought-provoking insight
      - Use simple, clear English
      - Suitable for a 60-second video
      
      Script format: Just plain text, no markdown or bullet points.
      Only output the script itself, nothing else.
    PROMPT

    puts "🔄 Calling DeepSeek API..."

    response = @client.chat(
      parameters: {
        model: "deepseek-chat",
        messages: [
          { role: "system", content: "You are a crypto market analyst creating daily video scripts." },
          { role: "user", content: prompt }
        ],
        temperature: 0.8,
        max_tokens: 400
      }
    )

    script = response.dig("choices", 0, "message", "content").strip
    
    if script.nil? || script.empty?
      puts "⚠️  Empty response from API"
      return "Script generation failed. Please try again."
    end
    
    script
  rescue => e
    puts "❌ API Error: #{e.message}"
    puts "Response: #{response.inspect}" if defined?(response)
    "Error generating script: #{e.message}"
  end

  def display_and_save(script, news)
    puts "\n" + "=" * 70
    puts "📊 DAILY CRYPTO SCRIPT"
    puts "📅 #{Date.current.strftime('%B %d, %Y')}"
    puts "=" * 70
    puts "\n📰 Source News Preview:\n#{news[0..200]}...\n" if news.length > 200
    puts "\n🎙️  SCRIPT:\n#{script}"
    puts "\n📊 Stats: #{script.split.length} words | #{script.length} characters"
    puts "=" * 70
    
    # 保存到文件
    filename = "crypto_script_#{Date.current.strftime('%Y%m%d')}.txt"
    File.write(filename, script)
    puts "💾 Saved to: #{filename}"
  end

  def get_fallback_news
    <<~FALLBACK
      Bitcoin holds above $65,000 with institutional inflows continuing
      Ethereum gas fees drop 30% following network upgrade
      Gold prices consolidate near $2,080 as dollar weakens
      Global crypto market cap reaches $2.8 trillion
      Major banks explore blockchain for cross-border payments
      Solana leads altcoin rally with 15% weekly gain
      Crypto regulations evolve in major economies
    FALLBACK
  end
end