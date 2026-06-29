# crypto_script_generator_advanced.rb
require "openai"
require "net/http"
require "json"
require "rss"
require "date"

class CryptoScriptGenerator
  def initialize
    access_key_id = ENV['DEEPSEEK_API_KEY']
    @client = OpenAI::Client.new(
      access_token: access_key_id,
      uri_base: "https://api.deepseek.com/v1"
    )
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
        
        feed.items.first(3).each do |item|
          all_news << "• #{item.title}"
          all_news << "  #{item.description&.gsub(/<[^>]*>/, '')&.strip}" if item.description
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
    PROMPT

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

    response.dig("choices", 0, "message", "content").strip
  end

  def display_and_save(script, news)
    puts "\n" + "=" * 70
    puts "📊 DAILY CRYPTO SCRIPT"
    puts "📅 #{Date.current.strftime('%B %d, %Y')}"
    puts "=" * 70
    puts "\n📰 Source News:\n#{news[0..300]}...\n"
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
    FALLBACK
  end
end
