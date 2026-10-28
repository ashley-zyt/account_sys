# 批量拉取主语言并写入 Kol.language
#
# 用法：
#   bundle exec rails runner scripts/fetch_store_language.rb [brandId] [platform] [dry]
#   默认 binance.us youtube
#   加 dry 只预览映射、不落库
#
# 流程：
#   1. 从 brand_contacts_*.json 读取创作者，按 notes 里的 creatorId 匹配到已入库 Kol
#   2. 逐个调 /youtube/profile 拉 mainLanguage（0.1 积分/人），结果缓存到 brand_languages_*.json
#   3. ISO 639-3 → 中文名 → Language.find_or_create_by_name → 写入 Kol.language_id

require 'net/http'
require 'json'
require 'uri'

API_KEY  = ENV['CREATORDB_API_KEY']
BASE_URL = 'https://apiv3.creatordb.app'

# ISO 639-3 → 中文语言名（覆盖这批数据常见语言；未命中则保留原代码）
LANG_NAMES = {
  'eng' => '英语', 'spa' => '西班牙语', 'por' => '葡萄牙语', 'ara' => '阿拉伯语',
  'hin' => '印地语', 'urd' => '乌尔都语', 'ben' => '孟加拉语', 'tam' => '泰米尔语',
  'tel' => '泰卢固语', 'mar' => '马拉地语', 'guj' => '古吉拉特语',
  'ind' => '印尼语', 'msa' => '马来语', 'vie' => '越南语', 'tha' => '泰语',
  'khm' => '高棉语', 'tgl' => '菲律宾语', 'fil' => '菲律宾语',
  'zho' => '中文', 'jpn' => '日语', 'kor' => '韩语',
  'rus' => '俄语', 'ukr' => '乌克兰语', 'pol' => '波兰语', 'ces' => '捷克语',
  'slk' => '斯洛伐克语', 'srp' => '塞尔维亚语', 'hrv' => '克罗地亚语',
  'fra' => '法语', 'deu' => '德语', 'ita' => '意大利语', 'nld' => '荷兰语',
  'ron' => '罗马尼亚语', 'hun' => '匈牙利语', 'ell' => '希腊语', 'bul' => '保加利亚语',
  'swe' => '瑞典语', 'fin' => '芬兰语', 'est' => '爱沙尼亚语', 'kat' => '格鲁吉亚语',
  'kaz' => '哈萨克语', 'tur' => '土耳其语', 'heb' => '希伯来语',
  'sin' => '僧伽罗语', 'afr' => '南非荷兰语', 'mlt' => '马耳他语',
}.freeze

def sanitize(str)
  str.to_s.gsub(/[^a-zA-Z0-9._-]/, '_')
end

def api_post(path, body = {})
  uri = URI("#{BASE_URL}#{path}")
  req = Net::HTTP::Post.new(uri)
  req['Content-Type'] = 'application/json'
  req['api-key'] = API_KEY
  req.body = body.to_json

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.open_timeout = 30
  http.read_timeout = 90

  resp = http.request(req)
  JSON.parse(resp.body)
rescue => e
  { 'error' => e.message }
end

def profile_key(platform)
  platform == 'youtube' ? 'channelId' : 'uniqueId'
end

def lang_name(code)
  LANG_NAMES.fetch(code.to_s.strip, code.to_s.strip)
end

def run
  if API_KEY.blank?
    puts '[错误] 未设置 CREATORDB_API_KEY 环境变量'
    exit 1
  end

  brand_id = ARGV[0] || 'binance.us'
  platform = ARGV[1] || 'youtube'
  dry_run  = ARGV.include?('dry')

  creators_path = Rails.root.join('tmp', 'creatordb', "brand_contacts_#{sanitize(brand_id)}_#{platform}.json")
  lang_cache    = Rails.root.join('tmp', 'creatordb', "brand_languages_#{sanitize(brand_id)}_#{platform}.json")

  unless File.exist?(creators_path)
    puts "[错误] 找不到文件：#{creators_path}"
    exit 1
  end

  creators = JSON.parse(File.read(creators_path))

  # 已入库 Kol 的 creatorId → Kol 映射（从 notes JSON 解析 creatorId）
  kol_by_creator = {}
  Kol.where(owner: '杜维').find_each do |kol|
    parsed = JSON.parse(kol.notes) rescue nil
    kol_by_creator[parsed['creatorId']] = kol if parsed && parsed['creatorId'].present?
  end

  # 只处理能匹配到已入库 Kol 的创作者
  matched = creators.select { |c| kol_by_creator.key?(c['creatorId']) }
  puts "已入库且可匹配的创作者：#{matched.size} 个"

  # 语言缓存（creatorId => { mainLanguage, displayName }）
  languages = File.exist?(lang_cache) ? (JSON.parse(File.read(lang_cache)) rescue {}) : {}

  # Phase 1: 拉取 mainLanguage（边拉边缓存）
  todo = matched.reject { |c| languages.key?(c['creatorId']) }
  puts "\n拉取 mainLanguage（待拉 #{todo.size} 人，0.1 积分/人）..."
  todo.each_with_index do |c, i|
    id = c['creatorId']
    resp = api_post("/#{platform}/profile", { profile_key(platform) => id, 'fields' => ['mainLanguage'] })
    languages[id] = { 'mainLanguage' => resp.dig('data', 'mainLanguage'), 'displayName' => c['displayName'] }
    File.write(lang_cache, JSON.pretty_generate(languages))
    puts "  [#{i + 1}/#{todo.size}] #{c['displayName']} -> #{resp.dig('data', 'mainLanguage').inspect}"
  end

  # Phase 2: 映射 + 写库
  puts "\n写库（#{dry_run ? '预览，不落库' : '正式写入'}）..."
  updated = 0
  skipped_no_lang = 0

  matched.each do |c|
    kol = kol_by_creator[c['creatorId']]
    next if kol.nil?

    code = languages.dig(c['creatorId'], 'mainLanguage')
    if code.blank?
      puts "跳过(无语言): #{kol.name}"
      skipped_no_lang += 1
      next
    end

    name = lang_name(code)
    lang = Language.find_or_create_by_name(name)

    if dry_run
      puts "[dry] #{kol.name}: #{code} -> #{lang.name}"
    else
      kol.update_columns(language_id: lang.id, updated_at: Time.current)
      updated += 1
      puts "更新: #{kol.name}: #{code} -> #{lang.name}"
    end
  end

  puts "\n完成：更新 #{updated} 条，跳过无语言 #{skipped_no_lang} 条#{dry_run ? '（预览，未落库）' : ''}"
end

run
