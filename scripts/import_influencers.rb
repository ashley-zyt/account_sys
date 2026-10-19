# 导入大V（Influencer）脚本
#
# 用法：
#   bundle exec rails runner scripts/import_influencers.rb /path/to/大V.txt          # 预览（不落库）
#   bundle exec rails runner scripts/import_influencers.rb /path/to/大V.txt confirm  # 执行导入
#
# 文件格式：TSV（制表符分隔，字段内含换行/制表符时需用双引号包裹）
#   表头：昵称/账号  备注  账号ID  账号链接
#   字段映射：
#     - 昵称/账号 → username
#     - 账号链接   → account_url
#     - 账号ID     → user_id
#     - 备注       → remark
#     - domain_id  → 固定 1
#     - platform   → 固定 twitter（这批均为 X 平台大V）
#   去重：按 username（唯一索引），已存在则更新其余字段（幂等，可重复执行）
file = ARGV[0]
confirm = ARGV[1] == 'confirm'

if file.blank? || !File.exist?(file)
  abort "用法: bundle exec rails runner scripts/import_influencers.rb <文件路径> [confirm]\n文件不存在: #{file}"
end

require 'csv'

rows = []
CSV.foreach(file, col_sep: "\t", headers: true, encoding: 'bom|utf-8', liberal_parsing: true) do |row|
  rows << row.to_h
end

puts "共解析 #{rows.size} 行数据"
puts confirm ? "=== 执行导入 ===" : "=== 预览（加 confirm 参数才真正落库）==="

created = 0
updated = 0
failed = 0

rows.each do |row|
  username    = row['昵称/账号'].to_s.strip
  account_url = row['账号链接'].to_s.strip
  user_id     = row['账号ID'].to_s.strip
  remark      = row['备注'].to_s.strip

  if username.blank?
    puts "  跳过（昵称/账号为空）: account_url=#{account_url}"
    next
  end

  influencer = Influencer.find_by(username: username) || Influencer.new(username: username)
  is_new = influencer.new_record?
  influencer.assign_attributes(
    user_id:     user_id.presence,
    account_url: account_url.presence,
    domain_id:   1,
    remark:      remark.presence,
    platform:    influencer.platform.presence || 'twitter'
  )

  unless confirm
    puts "  #{is_new ? '新增' : '更新'}: #{username}  →  #{account_url}"
    next
  end

  if influencer.save
    is_new ? created += 1 : updated += 1
  else
    failed += 1
    puts "  失败: #{username} - #{influencer.errors.full_messages.join(', ')}"
  end
end

puts "完成：新增 #{created}，更新 #{updated}，失败 #{failed}"
