# 导入大V（Influencer）脚本（支持 Excel .xlsx）
#
# 用法：
#   bundle exec rails runner scripts/import_influencers.rb /path/to/大V.xlsx          # 预览（不落库）
#   bundle exec rails runner scripts/import_influencers.rb /path/to/大V.xlsx confirm  # 执行导入
#
# 文件格式：Excel .xlsx，第 1 行为表头，列顺序：
#   列1 昵称/账号 → username
#   列2 备注     → remark
#   列3 账号ID   → user_id
#   列4 账号链接 → account_url
#   列5 主题     → theme（可选，无则留空待录入）
#   固定：platform = 'twitter'
# 去重：按 username（唯一索引），已存在则更新其余字段（幂等，可重复执行）
#
# 注意：账号ID 列建议在 Excel 里设为「文本」格式，避免 18 位大整数被 Excel 转成
#       浮点数丢失精度（X 的 user_id 是长数字）。
file = ARGV[0]
confirm = ARGV[1] == 'confirm'

if file.blank? || !File.exist?(file)
  abort "用法: bundle exec rails runner scripts/import_influencers.rb <xlsx路径> [confirm]\n文件不存在: #{file}"
end

require 'roo'

xlsx  = Roo::Spreadsheet.open(file)
sheet = xlsx.sheet(0)

rows = []
(2..sheet.last_row.to_i).each do |i|
  username = sheet.cell(i, 1).to_s.strip
  next if username.blank?

  raw_user_id = sheet.cell(i, 3)
  user_id = raw_user_id.nil? ? "" : raw_user_id.to_s.strip.sub(/\.0$/, '')

  rows << {
    username:    username,
    remark:      sheet.cell(i, 2).to_s.strip,
    user_id:     user_id,
    account_url: sheet.cell(i, 4).to_s.strip,
    theme:       sheet.cell(i, 5).to_s.strip
  }
end

puts "共解析 #{rows.size} 行数据"
puts confirm ? "=== 执行导入 ===" : "=== 预览（加 confirm 参数才真正落库）==="

created = 0
updated = 0
failed  = 0

rows.each do |row|
  influencer = Influencer.find_by(username: row[:username]) || Influencer.new(username: row[:username])
  is_new = influencer.new_record?
  influencer.assign_attributes(
    user_id:     row[:user_id].presence,
    account_url: row[:account_url].presence,
    theme:       row[:theme].presence,
    remark:      row[:remark].presence,
    platform:    influencer.platform.presence || 'twitter'
  )

  unless confirm
    puts "  #{is_new ? '新增' : '更新'}: #{row[:username]}  →  #{row[:account_url]}"
    next
  end

  if influencer.save
    is_new ? created += 1 : updated += 1
  else
    failed += 1
    puts "  失败: #{row[:username]} - #{influencer.errors.full_messages.join(', ')}"
  end
end

puts "完成：新增 #{created}，更新 #{updated}，失败 #{failed}"
