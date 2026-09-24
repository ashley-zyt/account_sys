# ===== 清理失效视频资源（preview / confirm 两阶段）=====
#
# 逻辑：
#   1. 从 task_log 找出 error_msg 含「失效关键词」（404 / URL / not found / expired 等）的失败日志
#   2. 按 task_uuid 反查各资源队列任务（搬运剪映/搬运混剪/剪映/花生/Notebooklm/人工运营/Grok/Heygen）
#   3. 命中的任务即「失效视频资源」
#
# 用法：
#   预览（只扫描列清单，不删任何数据）：
#     bundle exec rails runner scripts/clean_invalid_video_resources.rb
#   执行（真正删除）：
#     bundle exec rails runner scripts/clean_invalid_video_resources.rb confirm
#
# 注意：
#   - 只删库（资源队列任务），不动 OSS 文件（已失效 404 无需删）
#   - task_log 历史日志保留（它是日志，不是视频资源）
#   - 关键词可调：改下面 FAILURE_KEYWORDS 常量即可

FAILURE_KEYWORDS = ['404', 'media failed', '视频不存在', '视频失效'].freeze

confirm = (ARGV[0].to_s == 'confirm')

puts "==== #{confirm ? '执行清理' : '预览'}：失效视频资源 ===="
puts "失效关键词：#{FAILURE_KEYWORDS.join(' / ')}"
puts

# 1. 找失效日志
all_failed = TaskLog.where.not(error_msg: [nil, ''])
                    .select(:id, :task_uuid, :error_msg, :created_at).to_a
matched_logs = all_failed.select do |l|
  msg = l.error_msg.to_s.downcase
  FAILURE_KEYWORDS.any? { |k| msg.include?(k.downcase) }
end

puts "失效日志（error_msg 命中关键词）共 #{matched_logs.size} 条"
puts

# 2. 关键词命中分布（用于判断是否有误伤，如 url 太宽泛）
hits = Hash.new(0)
matched_logs.each do |l|
  msg = l.error_msg.to_s.downcase
  FAILURE_KEYWORDS.each { |k| hits[k] += 1 if msg.include?(k.downcase) }
end
puts "关键词命中分布："
hits.sort_by { |_k, v| -v }.each { |k, v| puts "  #{k}: #{v}" }
puts

# 3. 反查任务（task_uuid → 各资源队列表）
task_uuids = matched_logs.map(&:task_uuid).compact.uniq
models = WorkMode.resource_modes.map(&:task_model_class).compact

tasks_by_uuid = {}
models.each do |model|
  next unless model.column_names.include?('task_uuid')
  model.where(task_uuid: task_uuids).find_each { |t| tasks_by_uuid[t.task_uuid] = t }
end

by_model = Hash.new(0)
tasks_by_uuid.each_value { |t| by_model[t.class.name] += 1 }

puts "反查到失效视频资源任务 #{tasks_by_uuid.size} 条（按表）："
by_model.sort_by { |_k, v| -v }.each { |k, v| puts "  #{k}: #{v}" }
puts "未反查到任务的 task_uuid（日志还在、任务已删）: #{task_uuids.size - tasks_by_uuid.size} 个"
puts

# 4. 样例 error_msg（去重，让用户看清到底什么错误被匹配）
sample_msgs = matched_logs.map { |l| l.error_msg.to_s.strip }.reject(&:empty?).uniq.first(20)
if sample_msgs.any?
  puts "样例 error_msg（前 20 条去重）："
  sample_msgs.each { |m| puts "  · #{m[0, 120]}" }
  puts
end

# 5. 任务清单
if tasks_by_uuid.any?
  puts "失效任务清单（前 50 条）："
  tasks_by_uuid.values.first(50).each do |t|
    status = t.respond_to?(:status) ? t.status : '-'
    theme  = t.respond_to?(:theme) ? t.theme : '-'
    puts "  #{t.class.name}##{t.id} | #{t.task_uuid} | 状态=#{status} | 主题=#{theme}"
  end
  puts "  ...（共 #{tasks_by_uuid.size} 条）" if tasks_by_uuid.size > 50
  puts
end

# 6. confirm 删除
if confirm && tasks_by_uuid.any?
  puts "开始删除 #{tasks_by_uuid.size} 条失效视频资源..."
  deleted = 0
  models.each do |model|
    next unless model.column_names.include?('task_uuid')
    uuids = tasks_by_uuid.values.select { |t| t.class == model }.map(&:task_uuid)
    next if uuids.empty?
    deleted += model.where(task_uuid: uuids).delete_all
  end
  puts "✅ 已删除 #{deleted} 条失效视频资源任务"
elsif confirm
  puts "无失效视频资源，无需删除"
else
  puts "⚠️ 以上为预览，未做任何改动。确认无误后执行："
  puts "  bundle exec rails runner scripts/clean_invalid_video_resources.rb confirm"
end
