# 将所有 waiting_publish（等待发布/已分配）任务取消分配，重置回 pending
#
# 用法：
#   预览（只统计，不修改数据）：  bundle exec rails runner scripts/cancel_waiting_publish.rb
#   执行（真正取消分配）：        bundle exec rails runner scripts/cancel_waiting_publish.rb confirm
#
# 效果（与「等待重新分配」等价）：
#   status=pending、account_id=nil、browser_id=nil、start_at=nil、error_msg=nil

confirm = ARGV[0] == 'confirm'

total = 0
WorkMode.publishable_modes.each do |mode|
  model = mode.task_model_class
  scope = model.where(status: :waiting_publish)
  count = scope.count

  if confirm && count > 0
    scope.update_all(
      status: :pending,
      account_id: nil,
      browser_id: nil,
      start_at: nil,
      error_msg: nil,
      updated_at: Time.current
    )
  end

  total += count
  puts "#{mode.name}(#{model.name}): #{count} 条#{confirm && count > 0 ? ' [已取消分配]' : ''}"
end

if confirm
  puts "\n已完成：共取消分配 #{total} 条"
else
  puts "\n[预览模式] 共 #{total} 条 waiting_publish，未做任何修改。"
  puts "确认无误后执行：bundle exec rails runner scripts/cancel_waiting_publish.rb confirm"
end
