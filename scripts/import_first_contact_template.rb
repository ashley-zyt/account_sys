# 首次沟通话术（40 语种）导入脚本 —— 每个语言一个独立消息模板
#
# 功能：
#   1. 解析 scripts/data/first_contact_40languages.md（## N. 语言名 分节）
#   2. 每个语言小节创建一个独立模板，命名「首次沟通-<语言>」：
#      - 场景 = 首次建联，平台 = 通用，领域 = 数字货币
#      - 模板下只有一条该语言的 MessageTemplateVersion
#   3. 语言映射：「荷兰语」→ 系统语言「荷兰文」；
#      「塞尔维亚语（西里尔字母）」→ 系统语言「塞尔维亚-克罗地亚语」
#   4. ${name} 统一转为系统变量 ${NAME}，每个模板挂上 NAME 变量定义
#
# 幂等：按（模板名 + 领域）查找，已存在则更新其语言版本内容，不重复创建。
#
# 用法（服务器上执行）：
#   预览： bundle exec rails runner scripts/import_first_contact_template.rb
#   执行： EXEC=1 bundle exec rails runner scripts/import_first_contact_template.rb

DATA_FILE = Rails.root.join('scripts/data/first_contact_40languages.md')

DOMAIN_NAME   = '数字货币'
TEMPLATE_NAME = '首次沟通-%s' # % 语言名

# 文件语言名 → 系统语言名（未列出的按原名匹配）
LANG_ALIAS = {
  '荷兰语'                => '荷兰文',
  '塞尔维亚语（西里尔字母）' => '塞尔维亚-克罗地亚语'
}.freeze

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
    flag = lang ? 'ok' : '!! 未匹配语言'
    puts "  [#{flag}] #{TEMPLATE_NAME % lang_name}（#{s[:content].length} 字符）"
  end
  exit
end

domain = Domain.find_or_create_by!(name: DOMAIN_NAME)

# NAME 变量定义（全局唯一 identifier，所有模板共用）
name_var = MessageVariable.find_or_create_by!(identifier: 'NAME') do |v|
  v.name = 'KOL名称'
  v.description = 'KOL 名称/常用用户名，变量为空时自动使用 KOL 的 name 字段'
end

# ---- 每个语言一个独立模板 ----
imported = failed = 0
sections.each do |s|
  lang_name = LANG_ALIAS.fetch(s[:lang], s[:lang])
  lang = Language.find_by(name: lang_name)

  unless lang
    puts "[失败] #{lang_name}：系统中不存在该语言"
    failed += 1
    next
  end

  template = MessageTemplate.find_or_create_by!(name: TEMPLATE_NAME % lang_name, domain_id: domain.id) do |t|
    t.scenario = :first_contact
    t.platform = nil
  end
  template.message_template_variables.find_or_create_by!(message_variable_id: name_var.id)

  version = template.message_template_versions.find_or_initialize_by(language_id: lang.id)
  version.content = s[:content].gsub(/\$\{name\}/i, '${NAME}')
  version.save!

  imported += 1
  puts "[成功] #{template.name}（模板##{template.id}，语言版本##{version.id}）"
end

puts '=' * 50
puts "完成：导入 #{imported} 个模板，失败 #{failed}"
puts "「#{DOMAIN_NAME}」领域现有首次建联模板 #{MessageTemplate.where(scenario: :first_contact, domain_id: domain.id).count} 个"
