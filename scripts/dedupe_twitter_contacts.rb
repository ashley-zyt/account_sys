# 临时脚本：去重 twitter 联系方式 —— 相同 url 只保留 created_at 最晚的一条，删除其余。
#
# 背景：历史上存在重复录入（同一 @username 出现在多个 KOL 或多个联系方式）。
#   check_duplicate 唯一校验会拦截这些重复数据导致 KOL 状态无法更新。
#
# 规则：按 twitter 的 url 分组，每组仅保留 created_at 最新的一条，其余 destroy
#   （destroy 会触发 kol_messages 的 dependent: :nullify，消息保留、仅断开关联）。
#
# 用法（先预览，再执行）：
#   预览： bundle exec rails runner scripts/dedupe_twitter_contacts.rb
#   执行： EXEC=1 bundle exec rails runner scripts/dedupe_twitter_contacts.rb

PHASE_EXEC = ENV['EXEC'] == '1'

tw = KolContact.where(platform: KolContact.platforms[:twitter])

# 找出 url 重复的分组（只统计出现次数 > 1 的 url）
dup_urls = tw.group(:url).having('COUNT(*) > 1').count.keys

puts "重复的 twitter url：#{dup_urls.size} 个"
total_to_delete = 0
to_delete = []  # 待删除的联系方式 id

dup_urls.each do |url|
  contacts = tw.where(url: url).order(created_at: :desc, id: :desc).to_a
  keep = contacts.first          # 保留 created_at 最晚（id 最大）的一条
  removed = contacts[1..-1]      # 其余删除
  total_to_delete += removed.size
  removed.each do |c|
    to_delete << c.id
    puts "  [删] contact##{c.id} KOL##{c.kol_id} #{url}（保留 contact##{keep.id} KOL##{keep.kol_id}）"
  end
end

puts '=' * 60
puts "将保留 #{dup_urls.size} 条，删除 #{total_to_delete} 条重复联系方式"

exit unless PHASE_EXEC

deleted = 0
KolContact.where(id: to_delete).find_each do |c|
  c.destroy!
  deleted += 1
rescue => e
  Rails.logger.error "[DedupeTwitterContacts] contact##{c&.id} 删除异常: #{e.message}"
end

puts '=' * 60
puts "完成：已删除 #{deleted} 条重复 twitter 联系方式"
