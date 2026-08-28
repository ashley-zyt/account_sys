# ============================================================
# 工作模式统一注册表 改造后验证脚本（只读，不修改任何数据）
#
# 用法：
#   bundle exec rails runner scripts/verify_work_modes.rb
#
# 输出：[OK] 全部通过即代表改造行为与改造前等价；
#        [FAIL] 表示该处映射与预期不一致，需排查。
# ============================================================

def ok(label, cond, detail = nil)
  mark = cond ? "[OK]  " : "[FAIL]"
  line = "#{mark} #{label}"
  line += "  -> #{detail}" if detail
  puts line
end

def assert_set(label, actual, expected)
  a = actual.map(&:to_s).sort
  e = expected.map(&:to_s).sort
  ok(label, a == e, "实际=#{a.inspect} 期望=#{e.inspect}")
end

puts "===== 1. 枚举映射（应与改造前 8 个值完全一致） ====="
expected_enum = {
  "视频搬运" => 0, "coze" => 1, "剪映" => 2, "人工运营" => 3,
  "Grok" => 4, "Heygen" => 5, "花生" => 6, "Notebooklm" => 7
}
ok("Account.work_types", Account.work_types == expected_enum, Account.work_types.inspect)

puts "\n===== 2. 注册表条目 ====="
WorkMode.all.each do |m|
  puts "  #{m.enum_value}  #{m.name.ljust(8)} model=#{m.task_model.to_s.ljust(16)} 简称=#{m.short_name.ljust(6)} assign=#{m.scheduler_assign} publish=#{m.publish} manual=#{m.manual_assign} low_stock=#{m.low_stock_track}"
end

puts "\n===== 3. 中文名 -> 任务模型 映射 ====="
{
  "视频搬运" => "MoveTask", "剪映" => "JianyingTask", "人工运营" => "OperationTask",
  "Grok" => "GrokTask", "Heygen" => "HeygenTask", "花生" => "HuashengTask", "Notebooklm" => "NotebooklmTask"
}.each do |name, klass|
  m = WorkMode.all.find { |x| x.name == name }
  ok("#{name} -> #{klass}", m && m.task_model == klass)
end
ok("coze 无任务模型", WorkMode.all.find { |x| x.name == 'coze' }&.task_model.nil?)

puts "\n===== 4. 各调用点集合 ====="
assert_set("自动分配 scheduler_assign", WorkMode.scheduler_assign_modes.map(&:name), %w[视频搬运 剪映 花生 Notebooklm 人工运营 Grok])
assert_set("发布 publishable", WorkMode.publishable_modes.map(&:name), %w[视频搬运 剪映 花生 Notebooklm 人工运营 Grok Heygen])
assert_set("手动分配 manual_assign", WorkMode.manual_assign_map.keys, %w[视频搬运 人工运营 Grok Heygen 剪映 花生])
assert_set("低库存预警 low_stock", WorkMode.low_stock_track_modes.map(&:name), %w[视频搬运 剪映 Grok 花生])

puts "\n===== 5. 关联动态生成 ====="
bt = TaskLog.reflect_on_all_associations(:belongs_to).map(&:name)
assert_set("TaskLog belongs_to", bt, %w[move_task jianying_task grok_task operation_task heygen_task huasheng_task notebooklm_task log_account log_browser])
am = Account.reflect_on_all_associations(:has_many).map(&:name).map(&:to_s)
missing = %w[move_tasks jianying_tasks operation_tasks grok_tasks heygen_tasks huasheng_tasks notebooklm_tasks] - am
ok("Account has_many 含全部资源队列(含 notebooklm)", missing.empty?, "缺失 #{missing.inspect}")

puts "\n===== 6. 发布调度 dry-run（只读，不执行发布） ====="
tasks = PublishScheduler.fetch_all_tasks
puts "  fetch_all_tasks 返回 #{tasks.size} 条 waiting_publish 任务"
tasks.first(3).each do |t|
  m = WorkMode.for_model(t.class)
  puts "  - #{t.class.name}##{t.id}  type_name=#{m&.type_name}  video_field=#{m&.video_field}"
end
sample = tasks.first
if sample
  puts "  build_request_data 字段: #{PublishScheduler.build_request_data(sample).keys.inspect}"
end

puts "\n===== 完成 ====="
