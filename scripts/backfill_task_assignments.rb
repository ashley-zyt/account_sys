# 一次性回填：给「task_assignments 上线前已经发活、目前仍在途中」的任务补一条归属快照
#
# 为什么需要：
#   task_assignments 只对「新发活」的任务生效。在它上线之前就已经分配出去、目前还处于
#   waiting_publish / executing 的任务没有快照；这些任务若在回调前被释放（中断、超时兜底、
#   失败回退），task_logs 仍然会对不上账号/浏览器 —— 也就是要修的那个现象会在存量任务上继续出现。
#
# 用法：
#   rails runner scripts/backfill_task_assignments.rb              # 预览（默认，不写库）
#   rails runner scripts/backfill_task_assignments.rb CONFIRM=1    # 实际写入
#
# 安全性：
#   - 只 INSERT，不修改、不删除任何既有数据（非破坏性）
#   - 幂等：已有「未释放」快照的任务会被跳过，重复执行安全
#   - 只处理 account_id 非空的任务（没分配账号的本来就没有归属可记）

dry_run = ENV['CONFIRM'].to_s != '1'

puts '=' * 72
puts "task_assignments 存量回填#{dry_run ? '（预览模式，不写库；加 CONFIRM=1 实际写入）' : '（写入模式）'}"
puts '=' * 72

scanned   = 0
skipped   = 0
to_create = 0
per_mode  = Hash.new(0)
samples   = []

WorkMode.resource_modes.each do |mode|
  model = mode.task_model_class
  next if model.nil?

  # 只处理具备归属三要素（task_uuid / account_id / browser_id / status）的资源队列表，
  # 花生、NotebookLM 等表未必都有这些列，跳过即可（它们不走 report/回调这条日志链路）。
  cols = model.column_names
  unless %w[task_uuid account_id browser_id status].all? { |c| cols.include?(c) }
    puts "  跳过 #{mode.key}（#{model.name} 缺少 task_uuid/account_id/browser_id/status 中的列）"
    next
  end

  begin
    scope = model.where(status: [:waiting_publish, :executing]).where.not(account_id: nil)

    scope.find_each do |task|
      scanned += 1
      if task.task_uuid.blank?
        skipped += 1
        next
      end

      # 已有未释放快照 → 跳过（幂等）
      if TaskAssignment.for_task(task.task_uuid).unreleased.exists?
        skipped += 1
        next
      end

      unless dry_run
        TaskAssignment.record!(task)
      end

      to_create += 1
      per_mode[mode.key] += 1
      if samples.size < 15
        samples << format('  %-10s %-16s id=%-8s uuid=%s account=%s browser=%s status=%s',
                          mode.key, model.name, task.id, task.task_uuid,
                          task.account_id, task.browser_id, task.status)
      end
    end
  rescue => e
    puts "  处理 #{mode.key}（#{model.name}）时出错，已跳过：#{e.class} #{e.message}"
  end
end

puts
puts "扫描在途任务：#{scanned} 条"
puts "跳过（已有快照 / 无 task_uuid）：#{skipped} 条"
puts "#{dry_run ? '待补录' : '已补录'}：#{to_create} 条"
per_mode.each { |k, v| puts "    - #{k}: #{v}" }
puts
puts '样例（最多 15 条）：'
puts samples
puts
if dry_run
  puts '以上为预览，未写入任何数据。确认无误后执行：'
  puts '    rails runner scripts/backfill_task_assignments.rb CONFIRM=1'
else
  puts "完成：已补录 #{to_create} 条归属快照。"
end
puts '=' * 72
