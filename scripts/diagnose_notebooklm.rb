# ============================================================
# Notebooklm 资源分配链路诊断脚本（只读，不修改任何数据）
#
# 用法：bundle exec rails runner scripts/diagnose_notebooklm.rb
#
# 覆盖链路：
#   NotebooklmKeyword(status=3) → NotebooklmQueueScheduler 推送
#   → NotebooklmTask(pending) → TaskScheduler 按 theme+platform 匹配账号
#   → waiting_publish → PublishScheduler 发布
# ============================================================

def hr(title)
  puts "\n" + "=" * 60
  puts title
  puts "=" * 60
end

hr "1. 工作模式注册表配置"
mode = WorkMode.find("notebooklm")
if mode
  puts "  name=#{mode.name}  enum_value=#{mode.enum_value}  task_model=#{mode.task_model}"
  puts "  自动分配 scheduler_assign=#{mode.scheduler_assign}  发布 publish=#{mode.publish}  手动分配 manual_assign=#{mode.manual_assign}"
  puts "  → #{mode.scheduler_assign ? "已参与 TaskScheduler 自动分配" : "❌ 未参与自动分配！"}"
else
  puts "  ❌ 注册表里没有 notebooklm！"
end

hr "2. NotebooklmKeyword 状态分布（关键词储备）"
puts "  各状态数量："
NotebooklmKeyword.group(:status).count.sort.each do |s, c|
  puts "    status=#{s} (#{NotebooklmKeyword::STATUS_NAMES[s]}) : #{c} 条"
end
puts "  pushed 分布："
puts "    pushed=false : #{NotebooklmKeyword.where(pushed: false).count} 条"
puts "    pushed=true  : #{NotebooklmKeyword.where(pushed: true).count} 条"
waiting_push = NotebooklmKeyword.where(status: 3, pushed: false).count
puts "  待推送(status=3 且 pushed=false)：#{waiting_push} 条"
puts "  → #{waiting_push > 0 ? "有数据待推送（若任务表没数据，说明 NotebooklmQueueScheduler 没跑/没生效）" : "没有 status=3 的关键词（关键词还没生成完成）"}"

hr "3. NotebooklmTask 状态分布（资源队列）"
NotebooklmTask.group(:status).count.sort.each do |s, c|
  puts "    status=#{s} : #{c} 条"
end
pending = NotebooklmTask.where(status: :pending)
waiting = NotebooklmTask.where(status: :waiting_publish)
puts "  pending 任务：#{pending.count} 条"
puts "  waiting_publish 任务：#{waiting.count} 条"
puts "  pending 的 theme 列表：#{pending.distinct.pluck(:theme).inspect}"
puts "  pending 的 platform 列表：#{pending.distinct.pluck(:platform).inspect}"

hr "4. Notebooklm 账号情况"
accounts = Account.where(work_type: "Notebooklm")
puts "  work_type=Notebooklm 账号总数：#{accounts.count}"
puts "  其中正常(active)账号：#{accounts.active.count}"
puts "  账号状态分布：#{accounts.group(:status).count.inspect}"
active_accounts = accounts.active
puts "  active 账号 theme 列表：#{active_accounts.distinct.pluck(:theme).inspect}"
puts "  active 账号 platform 列表：#{active_accounts.distinct.pluck(:platform).inspect}"
puts "  → #{active_accounts.count.zero? ? "❌ 没有任何「正常」状态的 Notebooklm 账号，无法分配！" : "有正常账号"}"

hr "5. 关键匹配检查（pending 任务 × active 账号）"
pending_themes = pending.distinct.pluck(:theme).compact
active_themes  = active_accounts.distinct.pluck(:theme).compact
matching = pending_themes & active_themes
puts "  pending 任务 theme 与 active 账号 theme 的交集：#{matching.inspect}"
puts "  → #{matching.empty? ? "❌ 主题不匹配（分配不到账号）——常见原因：账号主题和关键词主题写法不一致" : "主题有交集"}"

puts "\n  pending 任务明细（前 30 条，检查每条是否有 theme+platform 都匹配的正常账号）："
pending.order(:id).limit(30).each do |t|
  has_account = active_accounts.where(theme: t.theme, platform: t.platform).exists?
  puts "    id=#{t.id}  theme=#{t.theme}  platform=#{t.platform}  → #{has_account ? "有可用账号 ✓" : "无可用账号 ✗"}"
end

hr "诊断完成"
