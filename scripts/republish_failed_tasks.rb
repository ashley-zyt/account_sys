# 补发脚本：机器端故障恢复后，把失败任务重置回 pending 重新下发。
#
# 用法：
#   bundle exec rails runner scripts/republish_failed_tasks.rb                 # 预览（今天）
#   bundle exec rails runner scripts/republish_failed_tasks.rb confirm          # 执行重置（今天）
#   bundle exec rails runner scripts/republish_failed_tasks.rb confirm 2026-10-20  # 指定日期
#
# 逻辑：
#   1. 遍历所有资源队列，找指定日期 failed 的任务
#   2. 跳过「资源失效」的（error_msg 含「资源失效」，重置也注定失败）
#   3. 其余（渠道耗尽/其他失败）重置：failure_count=0、status=pending、清空账号/浏览器/开始时间/错误
require 'date'

confirm = ARGV.include?('confirm')
date_arg = ARGV.reject { |a| a == 'confirm' }.first
target_date = date_arg.present? ? Date.parse(date_arg) : Date.today
day_range = target_date.beginning_of_day..target_date.end_of_day

total = 0
skipped = 0
reset = 0
details = []

WorkMode.resource_modes.each do |mode|
  model = mode.task_model_class
  failed = model.where(status: model.statuses[:failed]).where(updated_at: day_range)
  next if failed.count.zero?

  failed.find_each do |task|
    total += 1
    if task.error_msg.to_s.include?('资源失效')
      skipped += 1
      details << "[跳过·资源失效] #{model.name}##{task.id} #{task.error_msg.to_s[0, 40]}"
    else
      reset += 1
      details << "[将重置] #{model.name}##{task.id} failure_count=#{task.failure_count} #{task.error_msg.to_s[0, 40]}"
      if confirm
        task.update_columns(
          status: model.statuses[:pending],
          account_id: nil,
          browser_id: nil,
          failure_count: 0,
          error_msg: nil,
          start_at: nil,
          updated_at: Time.current
        )
      end
    end
  end
end

puts "日期 #{target_date} 失败任务总计 #{total} 个：跳过(资源失效) #{skipped}，可重置 #{reset}"
details.each { |d| puts "  #{d}" }

if confirm
  puts "已重置 #{reset} 个任务回 pending（failure_count=0）"
  puts "下一步：重新分配发布（如 bundle exec rails runner 'PublishScheduler.run'）"
else
  puts "预览模式，未执行。加 confirm 参数执行重置。"
end
