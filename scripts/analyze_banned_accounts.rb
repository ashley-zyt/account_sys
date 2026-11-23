# 分析近 N 天 twitter/instagram 账号「封禁/退出登录」的公共规律
# 运行：bundle exec rails runner scripts/analyze_banned_accounts.rb
#
# 口径：account_change_logs 中 abnormal_type ∈ {banned(封禁), logged_out(退出登录)} 的系统自动记录
#      （与 admin/data_alerts#banned 页面一致，聚焦机器端批量检测出的异常，人工改状态不在此统计内）

DAYS = 7
TARGET_PLATFORMS = %w[twitter instagram].freeze

def banner(title)
  puts "\n#{'=' * 64}"
  puts "  #{title}"
  puts '=' * 64
end

range_start = DAYS.days.ago.beginning_of_day
range_end   = Time.current

logs = AccountChangeLog
       .where(abnormal_type: [AccountChangeLog.abnormal_types[:banned],
                              AccountChangeLog.abnormal_types[:logged_out]])
       .where(changed_at: range_start..range_end)
       .to_a

accounts = Account.where(id: logs.map(&:account_id).uniq).index_by(&:id)

filtered = logs.select do |l|
  a = accounts[l.account_id]
  a && TARGET_PLATFORMS.include?(a.platform.to_s)
end

puts "近 #{DAYS} 天系统自动「封禁/退出登录」记录总数：#{logs.size}"
puts "其中 #{TARGET_PLATFORMS.join(' / ')} 的记录数：#{filtered.size}"

if filtered.empty?
  puts '目标平台无记录，结束。'
  exit
end

# 1. 时间分布
banner('1. 时间分布（按天）')
by_day = filtered.group_by { |l| [l.changed_at.to_date, accounts[l.account_id].platform.to_s] }
by_day.keys.map(&:first).uniq.sort.each do |day|
  tw = by_day[[day, 'twitter']] || []
  ig = by_day[[day, 'instagram']] || []
  puts format('  %s  twitter 封禁=%d 退出=%d | instagram 封禁=%d 退出=%d',
              day,
              tw.count { |l| l.abnormal_type == 'banned' },
              tw.count { |l| l.abnormal_type == 'logged_out' },
              ig.count { |l| l.abnormal_type == 'banned' },
              ig.count { |l| l.abnormal_type == 'logged_out' })
end

# 2. 封禁 vs 退出登录
banner('2. 封禁 vs 退出登录（按平台）')
TARGET_PLATFORMS.each do |p|
  ps = filtered.select { |l| accounts[l.account_id].platform.to_s == p }
  banned = ps.count { |l| l.abnormal_type == 'banned' }
  logout = ps.count { |l| l.abnormal_type == 'logged_out' }
  puts "  #{p}: 封禁=#{banned} 退出登录=#{logout}（合计 #{ps.size}）"
end

# 3. 命中关键词
banner('3. 命中关键词 matched_keyword')
filtered.group_by { |l| l.matched_keyword.presence || '(空)' }
        .sort_by { |_, v| -v.size }
        .each { |k, v| puts "  #{k}: #{v.size}" }

# 4. 发现动作
banner('4. 发现动作 source_action')
filtered.group_by { |l| l.source_action.presence || '(空)' }
        .sort_by { |_, v| -v.size }
        .each { |k, v| puts "  #{k}: #{v.size}" }

# 5. 错误信息样本
banner('5. 错误信息样本（去重前 20 条）')
filtered.map(&:error_msg).compact.reject(&:empty?).uniq.first(20).each_with_index do |m, i|
  puts "  #{i + 1}. #{m.to_s[0, 120]}"
end

# 6. 主题
banner('6. 主题分布')
filtered.group_by { |l| accounts[l.account_id]&.theme || '(空)' }
        .sort_by { |_, v| -v.size }
        .each { |k, v| puts "  #{k}: #{v.size}" }

# 7. 工作模式
banner('7. 工作模式分布')
filtered.group_by { |l| accounts[l.account_id]&.work_type.to_s.presence || '(空)' }
        .sort_by { |_, v| -v.size }
        .each { |k, v| puts "  #{k}: #{v.size}" }

# 8. 发布渠道
banner('8. 发布渠道分布')
filtered.group_by { |l| accounts[l.account_id]&.publish_channel.to_s.presence || '(空/默认)' }
        .sort_by { |_, v| -v.size }
        .each { |k, v| puts "  #{k}: #{v.size}" }

# 9. 浏览器
banner('9. 浏览器分布（profile_name）')
filtered.group_by { |l| accounts[l.account_id]&.browser&.profile_name || '(未绑定)' }
        .sort_by { |_, v| -v.size }
        .each { |k, v| puts "  #{k}: #{v.size}" }

# 10. 机器
banner('10. 机器分布（machine host）')
filtered.group_by { |l| accounts[l.account_id]&.browser&.machine_host || '(未知)' }
        .sort_by { |_, v| -v.size }
        .each { |k, v| puts "  #{k}: #{v.size}" }

# 10b. 代理 IP 分布
banner('10b. 代理 IP 分布（proxy_host）')
filtered.group_by { |l| accounts[l.account_id]&.browser&.proxy_host.presence || '(无代理)' }
        .sort_by { |_, v| -v.size }
        .each { |k, v| puts "  #{k}: #{v.size}" }

banner('10c. 代理 IP+端口分布（proxy_host:proxy_port）')
filtered.group_by do |l|
  b = accounts[l.account_id]&.browser
  b && b.proxy_host.present? ? "#{b.proxy_host}:#{b.proxy_port}" : '(无代理)'
end.sort_by { |_, v| -v.size }
   .each { |k, v| puts "  #{k}: #{v.size}" }

# 11. 运营人员
banner('11. 运营人员分布')
filtered.group_by { |l| accounts[l.account_id]&.operator.presence || '(空)' }
        .sort_by { |_, v| -v.size }
        .each { |k, v| puts "  #{k}: #{v.size}" }

# 12. 创建时间
banner('12. 创建时间分布（按月）')
filtered.group_by { |l| accounts[l.account_id]&.created_at&.strftime('%Y-%m') || '(空)' }
        .sort_by { |k, _| k.to_s }
        .each { |k, v| puts "  #{k}: #{v.size}" }

# 13. 具体账号清单
banner('13. 具体账号清单（最新 50 条）')
filtered.sort_by { |l| l.changed_at.to_i }.reverse.first(50).each do |l|
  a = accounts[l.account_id]
  puts format('  [%s] %-24s platform=%s status=%s theme=%s | %-10s @%s | kw=%s | action=%s | reason=%s',
              a&.id, (a&.account_name || '?').to_s[0, 24], a&.platform, a&.status, a&.theme,
              l.abnormal_type, l.changed_at&.strftime('%m-%d %H:%M'),
              l.matched_keyword, l.source_action, l.change_reason)
end

puts "\n分析完成。"
