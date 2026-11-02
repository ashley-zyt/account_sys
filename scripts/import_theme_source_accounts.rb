# ===== 把 theme_config.yml 里的对标账号导入 Theme.source_accounts =====
#
# 用法（生产服务器 Ruby 2.7.2，先跑 db:migrate 加字段）：
#   bundle exec rails runner scripts/import_theme_source_accounts.rb
#
# 只写数据库，不改 YAML。导入后 ThemeConfig.match_theme 改读数据库即可生效。

require 'yaml'

yaml_path = Rails.root.join('config/theme_config.yml')
config = YAML.load_file(yaml_path).deep_stringify_keys rescue {}

updated = 0
skipped = 0

config['themes']&.each do |name, data|
  theme = Theme.find_by(name: name)
  accounts = (data['source_accounts'] || []).map(&:to_s).map(&:strip).reject(&:empty?)

  if theme.nil?
    skipped += 1
    puts "[跳过] 主题不存在: #{name}"
    next
  end

  theme.update_column(:source_accounts, accounts.join("\n"))
  updated += 1
  puts "[导入] #{name}: #{accounts.size} 个对标账号"
end

puts "完成：导入 #{updated} 个主题，跳过 #{skipped} 个"
