# frozen_string_literal: true
# ============================================================
# 诊断：为什么 TaskScheduler.assign_resources(platform: 'twitter'/'instagram') 没有可分配资源
# ============================================================
# 只读脚本，不修改任何数据。逐层复现 assign_resources 的每道闸门，定位卡点。
#
# assign_resources 的分配链路（每道闸门都可能拦下所有账号）：
#   1. 账号层  ：Account.active + work_type=模式名 + platform=目标平台
#   2. 闸门层  ：跳过「今天已发布成功」/「已有 waiting_publish|executing 任务」的账号
#   3. 任务层  ：给候选账号分配「[platform, theme] 匹配 + 今天创建」的 pending 任务
#                ⚠️ 关键：只分配 created_at 在今天的 pending；昨天遗留的 pending 不参与分配
#
# 用法：bundle exec rails runner scripts/diagnose_assign_resources.rb
# ============================================================

TARGET_PLATFORMS = %w[twitter instagram].freeze

today       = Date.today
today_start = today.beginning_of_day
today_end   = today.end_of_day

puts "=" * 72
puts "assign_resources 无资源诊断（#{TARGET_PLATFORMS.join(' / ')}）"
puts "时间：#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
puts "=" * 72

# ---------- 零、参与分配的 work mode 清单 ----------
puts ""
puts "【零】参与分配的工作模式（scheduler_assign_modes）："
WorkMode.scheduler_assign_modes.each do |m|
  puts "  - #{m.name} → #{m.task_model}"
end

# ---------- 附：账号 work_type 是否有「不在注册表」的孤儿值 ----------
puts ""
puts "【附】Account.active 的 work_type 分布（检查是否有匹配不上的孤儿值）："
known_names = WorkMode.all.map(&:name)
dist = Account.active.group(:work_type).count
dist.each do |wt, n|
  flag = known_names.include?(wt.to_s) ? "" : "  ⚠️ 不在注册表中"
  puts "  #{wt.inspect}：#{n} 个#{flag}"
end

# ---------- 逐 mode 逐 platform 排查 ----------
WorkMode.scheduler_assign_modes.each do |mode|
  task_model = mode.task_model_class
  puts ""
  puts "▍【#{mode.name} / #{task_model.name}】"

  base_accounts = Account.active.where(work_type: mode.name)
  puts "  该 work_type 的 active 账号总数：#{base_accounts.count} 个"

  TARGET_PLATFORMS.each do |platform|
    puts ""
    puts "  ── #{platform} ──"
    accounts = base_accounts.where(platform: platform).to_a
    if accounts.empty?
      puts "    ❌ 账号层为空：该 work_type 下没有 #{platform} 账号"
      next
    end

    posted_today = []
    active_task  = []
    candidates   = []

    accounts.each do |account|
      if task_model.exists?(account_id: account.id, status: :success, actual_publish_time: today_start..today_end)
        posted_today << account
      elsif task_model.exists?(account_id: account.id, status: [:waiting_publish, :executing])
        active_task << account
      else
        candidates << account
      end
    end

    puts "    #{platform} 账号 #{accounts.size} 个："
    puts "      ├ 今天已发布成功（闸门1跳过）：#{posted_today.size} 个"
    puts "      ├ 已有 waiting_publish/executing（闸门2跳过）：#{active_task.size} 个"
    puts "      └ 通过闸门候选：#{candidates.size} 个"

    if candidates.empty?
      puts "    ❌ 闸门层：所有 #{platform} 账号都被「今天已发布」或「已有进行中任务」挡住"
      next
    end

    puts "    候选账号 theme：#{candidates.map(&:theme).uniq.join('、')}"

    candidates.each do |account|
      pending_scope = task_model.where(status: :pending, platform: platform, theme: account.theme)
      pending_all   = pending_scope.count
      pending_today = pending_scope.where(created_at: today_start..today_end).count

      if pending_today > 0
        puts "    ✅ #{account.account_name}(##{account.id}) theme=#{account.theme}：有 #{pending_today} 条今天创建的 pending 任务 → 可分配"
      else
        status_counts = task_model.where(platform: platform, theme: account.theme).group(:status).count
        newest = pending_scope.order(created_at: :desc).first
        puts "    ❌ #{account.account_name}(##{account.id}) theme=#{account.theme}："
        puts "         pending 总数=#{pending_all}，今天创建=#{pending_today}"
        puts "         该 [platform=#{platform}, theme=#{account.theme}] 全状态分布：#{status_counts.inspect}"
        puts "         最新一条 pending 创建于：#{newest ? newest.created_at.strftime('%m-%d %H:%M') : '（无）'}"
        if pending_all > 0 && pending_today == 0
          puts "         ↳ 原因：有 pending 但都是非今天创建（昨天/更早遗留），assign_resources 只分配今天的"
        elsif pending_all == 0
          puts "         ↳ 原因：该主题完全没有 pending 任务（任务池空了，或任务都已被领走/处理完）"
        end
      end
    end
  end
end

# ---------- 任务池总览 ----------
puts ""
puts "=" * 72
puts "任务池总览：各 platform/theme 的 pending 任务（今天 vs 遗留）"
puts "=" * 72
WorkMode.scheduler_assign_modes.each do |mode|
  task_model = mode.task_model_class
  TARGET_PLATFORMS.each do |platform|
    groups = task_model.where(status: :pending, platform: platform).group(:theme).count
    next if groups.empty?

    puts ""
    puts "  #{mode.name} / #{platform} 的 pending 任务："
    groups.sort_by { |_, n| -n }.each do |theme, total|
      today_cnt = task_model.where(status: :pending, platform: platform, theme: theme)
                            .where(created_at: today_start..today_end).count
      puts "    theme=#{theme.inspect}：共 #{total} 条（今天 #{today_cnt} / 遗留 #{total - today_cnt}）"
    end
  end
end

puts ""
puts "=" * 72
puts "诊断完成。"
puts "=" * 72
