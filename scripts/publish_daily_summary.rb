# -*- coding: utf-8 -*-
# 统计各平台：正常状态账号数、今日发文最终成功数、最终失败数
#
# 用法：bundle exec rails runner scripts/publish_daily_summary.rb
#
# 统计逻辑见 lib/publish_daily_summary.rb（与后台「今日发布状况」弹窗共用同一口径）

summary = PublishDailySummary.compute(Date.today)

# 中文/全角字符按双宽计算，保证表格对齐
def display_width(str)
  str.to_s.each_char.sum { |c| c.bytesize > 1 ? 2 : 1 }
end

def pad(str, width)
  str = str.to_s
  str + (" " * [width - display_width(str), 0].max)
end

puts "===== 发文统计（#{summary[:date].strftime('%Y-%m-%d')}）====="
puts "（成功/失败按账号去重，取今日最后一次执行结果）"
puts
puts "#{pad('平台', 12)}#{pad('正常账号', 10)}#{pad('最终成功', 10)}#{pad('最终失败', 10)}"

summary[:platforms].each do |p|
  puts "#{pad(p[:name], 12)}#{pad(p[:normal], 10)}#{pad(p[:success], 10)}#{pad(p[:failed], 10)}"
end

t = summary[:total]
puts
puts "#{pad('合计', 12)}#{pad(t[:normal], 10)}#{pad(t[:success], 10)}#{pad(t[:failed], 10)}"

# 最终失败的账号 ID 列表
failed = summary[:failed_accounts]
if failed.any?
  puts
  puts "--- 最终失败账号（#{failed.size} 个）---"
  failed.each do |f|
    name = f[:account_name] || "（账号已删除）"
    puts "##{f[:account_id]}  #{name}  [#{f[:platform] || '未知平台'}]"
  end
end
