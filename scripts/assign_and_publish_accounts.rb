# ===== 给指定一批账号分配任务并执行（preview / confirm 两阶段）=====
#
# 用途：手动给指定的一批账号各分配一条 pending 任务，并立即执行发布。
#       执行走 PublishScheduler.attempt_task，自动按账号渠道分叉：
#         - publish_channel = postforme → PostformePublisher（第三方 API）
#         - publish_channel = ag_center  → 机器端浏览器发布
#
# 用法：
#   预览（只扫描，不改任何数据）：
#     bundle exec rails runner scripts/assign_and_publish_accounts.rb 1,2,3
#   执行（真正分配 + 执行）：
#     bundle exec rails runner scripts/assign_and_publish_accounts.rb 1,2,3 confirm
#
# 注意：
#   - 只分配 status=pending 的任务（waiting_publish/executing 不碰，避免重复）
#   - attempt_task 自带「今日已发布」闸门：账号今天已 success 则重置回 pending 跳过，不重复发
#   - postforme 渠道账号需已授权（authorized），ag_center 账号需绑定浏览器 + machine_ip

account_ids = ARGV[0].to_s.split(',').map(&:strip).map(&:to_i).reject(&:zero?)
confirm = (ARGV[1].to_s == 'confirm')

if account_ids.empty?
  puts "用法：rails runner scripts/assign_and_publish_accounts.rb <id1,id2,id3> [confirm]"
else
  puts "==== #{confirm ? '执行' : '预览'}：给 #{account_ids.size} 个账号分配任务并执行 ===="
  puts

  ok = []
  skip = []
  error = []

  account_ids.each do |aid|
    account = Account.find_by(id: aid)
    unless account
      error << "账号 #{aid} 不存在"
      next
    end

    task_model = account.task_model_for_work_type
    unless task_model
      error << "#{account.account_name}（工作模式=#{account.work_type}）无资源队列"
      next
    end

    pending = task_model.where(status: :pending, platform: account.platform, theme: account.theme)
                        .order(:created_at).first
    unless pending
      skip << "#{account.account_name} 无可用 pending 资源（#{account.platform}/#{account.theme}）"
      next
    end

    desc = "#{account.account_name} → #{task_model.name}##{pending.id}（#{pending.platform}/#{pending.theme}，渠道=#{account.publish_channel}）"

    if confirm
      begin
        PublishScheduler.assign_to_account!(pending, account)
        PublishScheduler.attempt_task(pending)
        ok << desc
      rescue => e
        error << "#{account.account_name} 异常：#{e.message}"
      end
    else
      ok << desc
    end
  end

  puts "可分配执行 #{ok.size} 条："
  ok.each    { |s| puts "  ✅ #{s}" }
  puts "跳过 #{skip.size} 条："
  skip.each  { |s| puts "  ⏭ #{s}" }
  puts "失败 #{error.size} 条："
  error.each { |s| puts "  ❌ #{s}" }

  unless confirm
    puts
    puts "⚠️ 以上为预览，未做任何改动。确认无误后执行："
    puts "  bundle exec rails runner scripts/assign_and_publish_accounts.rb #{account_ids.join(',')} confirm"
  end
end
