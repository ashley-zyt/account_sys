# -*- coding: utf-8 -*-
# 取消指定平台「执行中」的发布任务，两层一起做：
#   1. account_sys 侧：executing → pending（重置，清掉账号/浏览器分配，重新排队）
#   2. 机器端：POST /tasks/clear?type={platform}_publish&status=running,queued
#      （中断 goroutine + 抑制回调，只清执行中/排队中，保留 success/failed 历史）
#
# 用法：
#   bundle exec rails runner scripts/cancel_executing_tasks.rb tiktok                          # 预览（只统计）
#   bundle exec rails runner scripts/cancel_executing_tasks.rb tiktok confirm                  # 执行（全部机器）
#   bundle exec rails runner scripts/cancel_executing_tasks.rb tiktok confirm ag15.juzhiic.com # 只处理某台机器
#
# 参数：
#   <platform>   目标平台：facebook / twitter / tiktok / youtube / instagram（必填）
#   confirm      加上才真正执行；不加只预览
#   [machine_ip] 可选，只处理指定机器；不传则处理所有配置了 machine_ip 的机器
#
# 效果（account_sys 侧）：status=pending、account_id=nil、browser_id=nil、start_at=nil、error_msg=nil
# 注意：只动 executing 状态；success / failed / pending / waiting_publish 一律不动。

platform     = ARGV[0].to_s.strip
confirm      = ARGV[1] == 'confirm'
only_machine = ARGV[2].to_s.strip

if platform.empty?
  puts "用法："
  puts "  bundle exec rails runner scripts/cancel_executing_tasks.rb <platform> [confirm] [machine_ip]"
  puts "  platform: facebook / twitter / tiktok / youtube / instagram"
  puts "  confirm:  加 confirm 才真正执行，否则只预览"
  puts "  machine_ip: 可选，只处理指定机器；不传则全部机器"
  exit 1
end

task_type = "#{platform}_publish"

models = WorkMode.publishable_modes
                 .map(&:task_model_class)
                 .select { |m| m.respond_to?(:platforms) && m.statuses.key?('executing') }

machines = only_machine.empty? ? MachineTaskMonitor.machine_ips : [only_machine]

puts "===== 取消 #{platform} 执行中任务（#{confirm ? '执行' : '预览'}）====="
puts ""
puts "目标机器：#{machines.empty? ? '(无)' : machines.join(', ')}"
puts ""

# ---------- 第 1 层：account_sys 侧统计 ----------
rows = []
total = 0
models.each do |model|
  count = model.where(platform: platform, status: :executing).count
  rows << [model, count]
  total += count
  puts format("  %-22s executing %d 条", model.name, count)
end
puts ""
puts "account_sys 侧合计：#{total} 条 executing"

unless confirm
  puts ""
  puts "这是预览，未做任何修改、未调机器端。确认无误后执行："
  puts "  bundle exec rails runner scripts/cancel_executing_tasks.rb #{platform} confirm#{only_machine.empty? ? '' : " #{only_machine}"}"
  exit
end

# ---------- 第 2 层：account_sys 侧重置 executing → pending ----------
puts ""
puts "===== ① account_sys 侧重置 ====="

done = 0
rows.each do |model, count|
  next if count.zero?
  n = model.where(platform: platform, status: :executing)
           .update_all(
             status: :pending,
             account_id: nil,
             browser_id: nil,
             start_at: nil,
             error_msg: nil,
             updated_at: Time.current
           )
  done += n
  puts format("  %-22s 已重置 %d 条 → pending", model.name, n)
end
puts "  account_sys 侧已重置 #{done} 条。"

# ---------- 第 3 层：机器端中断 running/queued ----------
puts ""
puts "===== ② 机器端中断（POST /tasks/clear）====="

if machines.empty?
  puts "  没有配置 machine_ip 的机器，跳过机器端调用。"
else
  clear_path = "/tasks/clear?type=#{task_type}&status=running,queued"
  machines.each do |ip|
    url = "https://#{ip}#{clear_path}"
    begin
      resp = RemoteApiClient.post(url, {}, read_timeout: 30)
      if resp.code.to_i == 200
        puts "  #{ip}  OK: #{resp.body.to_s[0, 120]}"
      else
        puts "  #{ip}  HTTP #{resp.code}: #{resp.body.to_s[0, 120]}"
      end
    rescue => e
      puts "  #{ip}  调用失败: #{e.message}"
    end
  end
end

puts ""
puts "===== 完成 ====="
puts "已取消 #{platform} 执行中任务：account_sys 重置 #{done} 条，机器端已触发中断。"
