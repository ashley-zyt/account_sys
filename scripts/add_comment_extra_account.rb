# 临时脚本：把指定账号追加到某主题的「额外参与评论」账号列表（幂等）。
# 用于让「浏览养护/无主题养号」等特殊账号跨主题参与评论互动，无需改状态和 theme。
#
# 用法：
#   bundle exec rails runner scripts/add_comment_extra_account.rb
#   可选 THEME=数字货币 ACCOUNT_IDS=934,935
#
# 会先校验目标主题是否满足评论条件（CommentThemeConfig 存在且 prompt 非空 + 有启用大V），
# 条件不满足会提示，但仍会写入 extra_account_ids（字段生效后由调度器判定）。

THEME       = ENV['THEME'] || '数字货币'
ACCOUNT_IDS = (ENV['ACCOUNT_IDS'] || '934').to_s.split(',').map(&:strip).reject(&:empty?).map(&:to_i).reject(&:zero?).uniq

abort '未指定账号' if ACCOUNT_IDS.empty?

config = CommentThemeConfig.find_by(theme: THEME)
if config.nil?
  puts "✗ 主题「#{THEME}」没有 CommentThemeConfig，无法挂额外账号"
  puts '  请先在「评论主题配置」页为该主题创建记录并填写 prompt'
  exit 1
end

if config.prompt.blank?
  puts "✗ 主题「#{THEME}」的 CommentThemeConfig.prompt 为空，即使挂上账号，generate_tasks_for 也会跳过"
end

puts '=' * 60
puts "主题「#{THEME}」评论条件校验"
puts '=' * 60
puts "  CommentThemeConfig 存在: 是"
puts "  prompt 非空: #{config.prompt.present? ? '是' : '否 ✗'}"
inf_count = Influencer.enabled.where(theme: THEME).count
puts "  启用大V数: #{inf_count} #{inf_count.zero? ? '✗（无启用大V，无发文来源）' : ''}"
today_posts = InfluencerPost.where(influencer_id: Influencer.enabled.where(theme: THEME).pluck(:id))
                            .where(posted_at: Time.current.beginning_of_day..Time.current.end_of_day).count
puts "  今日发文数: #{today_posts}"

# 校验账号是否存在、是否 twitter
puts "\n账号校验"
ACCOUNT_IDS.each do |aid|
  a = Account.unscoped.find_by(id: aid)
  if a.nil?
    puts "  ✗ 账号 #{aid} 不存在"
    next
  end
  platform_ok = a.platform.to_s == 'twitter'
  puts "  账号 #{aid} #{a.account_name}: 平台=#{a.platform} 状态=#{a.status} #{platform_ok ? '' : '✗（非 twitter，评论下发会失败）'}"
end

# 幂等追加
existing = config.extra_account_ids_list
merged = (existing + ACCOUNT_IDS).uniq
config.update!(extra_account_ids: merged.join(','))

puts "\n写入完成：主题「#{THEME}」extra_account_ids = #{merged.join(',')}"
puts "（原值：#{existing.join(',')}）"
puts "\n提示：写入后还需服务器执行 bundle exec rails db:migrate 使 extra_account_ids 字段生效，"
puts "否则 CommentThemeConfig.extra_account_ids 读取会报 undefined method。"
