# 临时脚本：诊断某账号今日为什么没有（或是否已）参与评论互动。
# 只读，不改库。支持两种参与路径：
#   A. 正常账号：状态「正常」+ X 平台 + theme 直接匹配主题
#   B. 额外账号：配置在某个主题的 CommentThemeConfig.extra_account_ids 里（跨主题，豁免状态/theme）
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
puts "  状态: #{account.status}"
puts "  主题 theme: #{account.theme.inspect}"
puts "  工作模式: #{account.work_type}"
browser = account.browser
puts "  浏览器: #{browser ? '已绑定' : '未绑定'}"
if browser
  puts "    machine_host: #{browser.machine_host.inspect}"
  puts "    profile_name: #{browser.profile_name.inspect}"
  puts "    云手机: #{browser.cloud_phone? ? '是（会被拦截）' : '否'}"
end

# 2. 参与路径判定
puts "\n【2. 参与路径判定】"
platform_ok = account.platform.to_s == 'twitter'
status_normal = account.status == '正常'

extra_hits = CommentThemeConfig.where("extra_account_ids IS NOT NULL AND extra_account_ids <> ''")
                               .select { |c| c.extra_account_ids_list.include?(ACCOUNT_ID) }

if !platform_ok
  puts "  ✗ 平台不是 twitter，两种路径都会被过滤，永不选中"
  puts "  （其余检查已无意义，请确认账号平台）"
  exit 1
end

normal_theme_config = account.theme.present? ? CommentThemeConfig.find_by(theme: account.theme) : nil

path_a = platform_ok && status_normal && normal_theme_config&.prompt.present?
path_b = extra_hits.any?

puts "  路径A（正常账号 theme 匹配）: #{path_a ? '✓ 可用' : '✗ 不可用'}"
puts "  路径B（额外账号跨主题参与）: #{path_b ? '✓ 可用（' + extra_hits.map(&:theme).join('、') + '）' : '✗ 未配置'}"

unless path_a || path_b
  puts "\n  ✗ 两条路径都不通，因此不会被评论调度选中"
end

# 3. 逐条路径检查可评论对象（发文）
puts "\n【3. 可评论对象检查】"
checked_themes = []
checked_themes << account.theme if path_a
checked_themes.concat(extra_hits.map(&:theme)) if path_b
checked_themes = checked_themes.compact.uniq

if checked_themes.empty?
  puts "  无可用主题，无评论对象"
else
  checked_themes.each do |t|
    cfg = CommentThemeConfig.find_by(theme: t)
    inf_enabled = Influencer.enabled.where(theme: t)
    today_posts = InfluencerPost.where(influencer_id: inf_enabled.pluck(:id))
                                .where(posted_at: Time.current.beginning_of_day..Time.current.end_of_day)
    prompt_ok = cfg&.prompt.present?
    puts "  主题「#{t}」: prompt=#{prompt_ok ? '✓' : '✗'} 启用大V=#{inf_enabled.count} 今日发文=#{today_posts.count}"
    puts "    ✗ 该主题今日无发文" if today_posts.none?
  end
end

# 4. 该账号今日评论任务情况
puts "\n【4. 今日评论任务】"
today_tasks = CommentTask.where(account_id: account.id)
                         .where(created_at: Time.current.beginning_of_day..Time.current.end_of_day)
puts "  今日已生成评论任务数: #{today_tasks.count}（上限 #{CommentScheduler::MAX_COMMENTS_PER_DAY}）"
today_tasks.order(:id).each do |t|
  post = t.influencer_post
  puts "    task##{t.id} status=#{t.status} 发文##{post&.id}（#{post&.influencer&.username} / #{post&.influencer&.theme}）"
end
if today_tasks.count >= CommentScheduler::MAX_COMMENTS_PER_DAY
  puts "  ✗ 已达每日上限 #{CommentScheduler::MAX_COMMENTS_PER_DAY}，今天不会再分配评论"
end

# 5. 今日全局评论互动概况
puts "\n【5. 今日全局评论互动概况】"
total_today = CommentTask.where(created_at: Time.current.beginning_of_day..Time.current.end_of_day)
puts "  今日全局评论任务总数: #{total_today.count}"
puts "  其中 pending/queued/running: #{total_today.where(status: [:pending, :queued, :running]).count}"
puts "  其中 success: #{total_today.where(status: :success).count}"

puts "\n【排查结论】"
if (path_a || path_b) && today_tasks.count < CommentScheduler::MAX_COMMENTS_PER_DAY
  puts "  账号有参与路径、且今日未达上限。若还没评论，最可能是："
  puts "  ① 目标主题今日无发文（见第3块） ② 调度器尚未跑到（每小时一轮） ③ 下发被浏览器硬条件拦截（缺 machine_host/profile_name/云手机）"
elsif today_tasks.count >= CommentScheduler::MAX_COMMENTS_PER_DAY
  puts "  今日已发满 #{CommentScheduler::MAX_COMMENTS_PER_DAY} 条，属正常停止"
else
  puts "  账号无可用参与路径（见第2块），需配置 theme prompt 或挂到某主题的 extra_account_ids"
end
