# ===== 诊断「抖音-视频号」主题花生资源不存在的原因 =====
#
# 用法（生产服务器 Ruby 2.7.2）：
#   bundle exec rails runner scripts/diagnose_douyin_shipinhao.rb

puts "===== 诊断「抖音-视频号」花生资源 ====="
puts

# 1. 常量值
theme = HuashengTask::DOUYIN_SHIPINHAO_THEME
puts "[1] DOUYIN_SHIPINHAO_THEME = #{theme.inspect}"
puts

# 2. 关键词里含「抖音」或「视频号」的主题分布（排查 theme 不匹配）
puts "[2] 关键词 theme 分布（含'抖音'或'视频号'）"
themes = HuashengKeyword.where("theme LIKE ? OR theme LIKE ?", "%抖音%", "%视频号%").group(:theme).count
if themes.empty?
  puts "  无任何 theme 含'抖音'或'视频号'的关键词"
else
  themes.each { |t, c| puts "  #{t.inspect}: #{c} 条" }
end
puts

# 3. 目标主题关键词的状态 / pushed 分布
puts "[3] theme=#{theme.inspect} 的关键词分布"
kw = HuashengKeyword.where(theme: theme)
if kw.empty?
  puts "  无该主题关键词"
else
  puts "  总数: #{kw.count}"
  puts "  status 分布: #{kw.group(:status).count.inspect}"
  puts "  pushed 分布: #{kw.group(:pushed).count.inspect}"
end
puts

# 4. 任务分布
puts "[4] HuashengTask platform='抖音-视频号' 的任务"
tasks = HuashengTask.where(platform: '抖音-视频号')
if tasks.empty?
  puts "  无任何 '抖音-视频号' 任务"
else
  puts "  总数: #{tasks.count}"
  puts "  status 分布: #{tasks.group(:status).count.inspect}"
  puts "  最近 5 条:"
  tasks.order(id: :desc).limit(5).each do |t|
    puts "    ##{t.id} status=#{t.status} keyword_id=#{t.huasheng_keyword_id} created=#{t.created_at&.strftime('%m-%d %H:%M')}"
  end
end
puts

# 5. status=3 但未 pushed 的关键词，检查 result_data 是否有 oss_url
puts "[5] status=3 的关键词 result_data 是否含 oss_url（未推送的）"
unpushed = kw.where(status: 3, pushed: false)
if unpushed.empty?
  puts "  无 status=3 且 pushed=false 的关键词"
else
  unpushed.each do |k|
    r = (JSON.parse(k.result_data) rescue {})
    puts "  keyword##{k.id} (#{k.keyword}) oss_url=#{r['oss_url'].present? ? '有' : '无'}"
  end
end
puts

puts "===== 诊断完成 ====="
