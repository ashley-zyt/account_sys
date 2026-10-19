# 导入大V（Influencer）脚本（支持 JSON）
#
# 用法：
#   bundle exec rails runner scripts/import_influencers_json.rb /path/to/大V.json          # 预览（不落库）
#   bundle exec rails runner scripts/import_influencers_json.rb /path/to/大V.json confirm  # 执行导入
#
# 文件格式：JSON，顶层对象含一个数组 key（如「加密KOL_Twitter合并清单」），数组每项字段：
#   昵称/账号 → username
#   备注     → remark
#   账号ID   → user_id
#   账号链接 → account_url
#   固定：domain_id = 1，platform = 'twitter'
# 去重：按 username（唯一索引），已存在则更新其余字段（幂等，可重复执行）
file = ARGV[0]
confirm = ARGV[1] == 'confirm'

if file.blank? || !File.exist?(file)
  abort "用法: bundle exec rails runner scripts/import_influencers_json.rb <json路径> [confirm]\n文件不存在: #{file}"
end

require 'json'

data = JSON.parse(File.read(file, encoding: 'bom|utf-8'))

# 顶层可能是 { key: [...] }，也可能是直接 [...]；统一取出数组
list =
  if data.is_a?(Hash)
    data.values.find { |v| v.is_a?(Array) } || []
  elsif data.is_a?(Array)
    data
  else
    []
  end

puts "共解析 #{list.size} 条记录"
puts confirm ? "=== 执行导入 ===" : "=== 预览（加 confirm 参数才真正落库）==="

created = 0
updated = 0
failed  = 0

list.each do |row|
  next unless row.is_a?(Hash)

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
