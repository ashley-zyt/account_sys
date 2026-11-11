# 临时脚本：诊断账号 934 今日为什么没有开始评论互动。
# 只读，不改库。逐项排查 CommentScheduler 的评论账号筛选链路。
#
# 用法：
#   bundle exec rails runner scripts/diagnose_comment_account.rb
#   可选 ACCOUNT_ID=934 换账号

ACCOUNT_ID = (ENV['ACCOUNT_ID'] || 934).to_i

account = Account.unscoped.find_by(id: ACCOUNT_ID)
abort "账号 #{ACCOUNT_ID} 不存在" if account.nil?

puts '=' * 60
puts "账号 #{account.id}：#{account.account_name}"
puts '=' * 60

# 1. 账号硬条件
puts "\n【1. 账号硬条件】"
puts "  平台: #{account.platform}（评论互动只认 twitter）"
puts "  状态: #{account.status}（评论互动只选「正常」）"
puts "  主题 theme: #{account.theme.inspect}"
puts "  工作模式: #{account.work_type}"
browser = account.browser
puts "  浏览器: #{browser ? '已绑定' : '未绑定'}"
if browser
  puts "    machine_host: #{browser.machine_host.inspect}"
  puts "    profile_name: #{browser.profile_name.inspect}"
  puts "    云手机: #{browser.cloud_phone? ? '是（会被拦截）' : '否'}"
end

# 2. 平台/状态是否达标
puts "\n【2. 资格判定】"
if account.platform.to_s != 'twitter'
  puts "  ✗ 平台不是 twitter，CommentScheduler.themed_accounts 直接过滤，永不选中"
end
if account.status != '正常'
  puts "  ✗ 状态不是「正常」，Account.active 过滤掉"
end
if account.platform.to_s == 'twitter' && account.status == '正常'
  puts "  ✓ 平台 + 状态达标"
end

# 3. theme 维度的评论配置与大V发文
puts "\n【3. 主题维度的评论配置与发文】"
theme = account.theme
if theme.blank?
  puts "  ✗ 账号 theme 为空，无法匹配任何大V主题"
else
  config = CommentThemeConfig.find_by(theme: theme)
  if config.nil?
    puts "  ✗ 主题「#{theme}」没有 CommentThemeConfig（未配评论 prompt），generate_tasks_for 会跳过"
  elsif config.prompt.blank?
    puts "  ✗ 主题「#{theme}」的 CommentThemeConfig.prompt 为空，generate_tasks_for 会跳过"
  else
    puts "  ✓ 主题「#{theme}」已配 prompt"
  end

  # 该 theme 是否在其它主题的 extra_account_ids 里（跨主题参与）
  extra_hits = CommentThemeConfig.where("extra_account_ids IS NOT NULL AND extra_account_ids <> ''")
                                 .select { |c| c.extra_account_ids_list.include?(ACCOUNT_ID) }
  if extra_hits.any?
    puts "  ✓ 该账号被配置为跨主题参与：#{extra_hits.map(&:theme).join('、')}"
  else
    puts "  （该账号未配置在任何主题的 extra_account_ids 里）"
  end

  # 该 theme 下的大V及今日发文
  influencers = Influencer.where(theme: theme)
  puts "  主题「#{theme}」大V数: #{influencers.count}（启用: #{influencers.enabled.count}）"
  today_posts = InfluencerPost.where(influencer_id: influencers.enabled.pluck(:id))
                              .where(posted_at: Time.current.beginning_of_day..Time.current.end_of_day)
  puts "  今日发文数: #{today_posts.count}"
  if today_posts.none?
    puts "  ✗ 主题「#{theme}」今天没有大V发文，无评论任务可生成"
  end
end

# 4. 该账号今日评论任务情况
puts "\n【4. 今日评论任务】"
today_tasks = CommentTask.where(account_id: account.id)
                         .where(created_at: Time.current.beginning_of_day..Time.current.end_of_day)
puts "  今日已生成评论任务数: #{today_tasks.count}（上限 #{CommentScheduler::MAX_COMMENTS_PER_DAY}）"
today_tasks.order(:id).each do |t|
  post = t.influencer_post
  puts "    task##{t.id} status=#{t.status} 发文##{post&.id}（#{post&.influencer&.username}）"
end
if today_tasks.count >= CommentScheduler::MAX_COMMENTS_PER_DAY
  puts "  ✗ 已达每日上限 #{CommentScheduler::MAX_COMMENTS_PER_DAY}，今天不会再分配评论"
end

# 5. 今日全局是否有评论任务在跑（判断调度器是否在正常工作）
puts "\n【5. 今日全局评论互动概况】"
total_today = CommentTask.where(created_at: Time.current.beginning_of_day..Time.current.end_of_day)
puts "  今日全局评论任务总数: #{total_today.count}"
puts "  其中 pending/queued/running: #{total_today.where(status: [:pending, :queued, :running]).count}"
puts "  其中 success: #{total_today.where(status: :success).count}"

puts "\n【排查结论】"
puts "  结合上面 ✗ 项定位 934 未参与评论的原因："
puts "  最常见是：① theme 不匹配/未配 prompt ② 平台非 twitter ③ 状态非正常 ④ 今日已达 2 条上限 ⑤ 今天该主题无大V发文"
