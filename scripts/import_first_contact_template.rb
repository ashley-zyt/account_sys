# 首次沟通话术（40 语种）导入脚本
#
# 功能：
#   1. 解析 scripts/data/first_contact_40languages.md（## N. 语言名 分节）
#   2. 在「数字货币」领域创建/更新消息模板「首次沟通话术」（场景=首次建联，平台=通用）
#   3. 每个语言小节创建/更新一条 MessageTemplateVersion，挂到对应 Language：
#      - 「荷兰语」→ 系统语言「荷兰文」
#      - 「塞尔维亚语（西里尔字母）」→ 系统语言「塞尔维亚-克罗地亚语」
#      - 「芬兰语」跳过（用户后续手动补录）
#   4. ${name} 统一转为系统变量 ${NAME}，并给模板挂上 NAME 变量定义
#
# 幂等：按（模板 + 语言）find_or_initialize，重复执行只更新内容。
#
# 用法（服务器上执行）：
#   预览： bundle exec rails runner scripts/import_first_contact_template.rb
#   执行： EXEC=1 bundle exec rails runner scripts/import_first_contact_template.rb

DATA_FILE = Rails.root.join('scripts/data/first_contact_40languages.md')

DOMAIN_NAME   = '数字货币'
TEMPLATE_NAME = '首次沟通话术'

# 文件语言名 → 系统语言名（未列出的按原名匹配）
LANG_ALIAS = {
  '荷兰语'                => '荷兰文',
  '塞尔维亚语（西里尔字母）' => '塞尔维亚-克罗地亚语'
}.freeze

SKIP_LANGS = ['芬兰语'].freeze

# ---- 解析文件 ----
sections = []
current = nil
File.foreach(DATA_FILE) do |line|
  if (m = line.match(/\A##\s+\d+\.\s+(.+?)\s*\z/))
    current = { lang: m[1], body: [] }
    sections << current
  elsif current
    current[:body] << line
  end
end

sections.each { |s| s[:content] = s[:body].join.strip }
sections.reject! { |s| s[:content].blank? }

puts "解析到 #{sections.size} 个语言版本"

if ENV['EXEC'] != '1'
  puts '--- 预览模式（加 EXEC=1 实际导入）---'
  sections.each do |s|
    lang_name = LANG_ALIAS.fetch(s[:lang], s[:lang])
    lang = Language.find_by(name: lang_name)
    flag = lang ? 'ok' : (SKIP_LANGS.include?(lang_name) ? '跳过' : '!! 未匹配')
    puts "  [#{flag}] #{s[:lang]} -> #{lang_name}（#{s[:content].length} 字符）"
  end
  exit
end

# ---- 模板与变量 ----
domain = Domain.find_or_create_by!(name: DOMAIN_NAME)
template = MessageTemplate.find_or_create_by!(name: TEMPLATE_NAME, domain_id: domain.id) do |t|
  t.scenario = :first_contact
  t.platform = nil
end

name_var = MessageVariable.find_or_create_by!(identifier: 'NAME') do |v|
  v.name = 'KOL名称'
  v.description = 'KOL 名称/常用用户名，变量为空时自动使用 KOL 的 name 字段'
end
template.message_template_variables.find_or_create_by!(message_variable_id: name_var.id)

# ---- 导入各语言版本 ----
imported = skipped = failed = 0
sections.each do |s|
  lang_name = LANG_ALIAS.fetch(s[:lang], s[:lang])

  if SKIP_LANGS.include?(lang_name)
    puts "[跳过] #{lang_name}（后续手动补录）"
    skipped += 1
    next
  end

  lang = Language.find_by(name: lang_name)
  unless lang
    puts "[失败] #{lang_name}：系统中不存在该语言"
    failed += 1
    next
  end

  version = template.message_template_versions.find_or_initialize_by(language_id: lang.id)
  version.content = s[:content].gsub(/\$\{name\}/i, '${NAME}')
  version.save!
  imported += 1
  puts "[成功] #{lang_name}（版本##{version.id}）"
end

puts '=' * 50
puts "完成：导入 #{imported} 个语言版本，跳过 #{skipped}，失败 #{failed}"
puts "模板：#{TEMPLATE_NAME}（id=#{template.id}，领域=#{DOMAIN_NAME}，共 #{template.message_template_versions.count} 个语言版本）"
