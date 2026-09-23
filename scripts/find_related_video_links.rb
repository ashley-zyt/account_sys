# -*- coding: utf-8 -*-
# 通过一个最终发文链接，反查「同一个源视频」在其他平台对应的发文链接
#
# 原理：同一个源内容（视频搬运 / 剪映 / 花生 / Notebooklm）会在剪映完成后，
#       按平台为每个平台建一条任务，这些任务共享同一个 group_id。
#       post_stats.url 没有 group_id，需先通过「账号 + 发文日期」回推到对应任务表
#       拿到 group_id，再反查同组其他平台任务。
#
# 覆盖模型（有「同源视频组」字符串 group_id 的）：
#   MoveTask(视频搬运) / JianyingTask(剪映) / HuashengTask(花生) / NotebooklmTask
# 不支持：
#   Grok / Heygen —— 单平台单任务，无 group_id（没有「同源多平台」概念）
#   人工运营 OperationTask —— group_id 是数字分组（bigint），语义不同
#
# 用法：bundle exec rails runner scripts/find_related_video_links.rb <发文链接>

# 有「同源视频组」（字符串 group_id）的任务模型，同一视频按平台拆多条任务
GROUPED_TASK_MODELS = [MoveTask, JianyingTask, HuashengTask, NotebooklmTask].freeze
MODEL_NAMES = {
  "MoveTask"      => "搬运剪映",
  "JianyingTask"  => "剪映",
  "HuashengTask"  => "花生",
  "NotebooklmTask" => "Notebooklm"
}.freeze

url = ARGV[0].to_s.strip
if url.empty?
  puts "用法：bundle exec rails runner scripts/find_related_video_links.rb <发文链接>"
  exit 1
end

post = PostStat.find_by(url: url)
unless post
  puts "未找到该发文链接对应的记录：#{url}"
  puts "提示：请确认链接与 post_stats.url 完全一致（大小写/参数都算）"
  exit 1
end

account = post.account
puts "输入链接：#{url}"
puts "所属账号：##{account.id} #{account.account_name}（平台=#{account.platform}，主题=#{account.theme}，模式=#{account.work_type}）"
puts "发文日期：#{post.post_date}"

# 回推该账号发布此视频的任务：遍历所有有 group_id 的任务模型，
# 优先「账号 + 发文日期当天 + success」匹配，兜底用标题匹配
date = post.post_date
task = nil
task_model = nil

GROUPED_TASK_MODELS.each do |model|
  t = model.where(account_id: account.id, status: :success)
           .where(actual_publish_time: date.beginning_of_day..date.end_of_day)
           .order(actual_publish_time: :desc)
           .first
  if t
    task = t
    task_model = model
    break
  end
end

# 兜底：日期匹配不到（时区/补录差异），用「账号 + 标题」匹配
if task.nil? && post.title.present?
  GROUPED_TASK_MODELS.each do |model|
    t = model.where(account_id: account.id, status: :success).where(title: post.title).first
    if t
      task = t
      task_model = model
      break
    end
  end
end

unless task
  puts
  puts "未找到对应的资源任务。可能原因："
  puts "  1. 该链接由 Grok / Heygen 产生（单平台单任务，无「同源多平台」概念）"
  puts "  2. 该链接由「人工运营」产生（其 group_id 为数字分组，语义不同，未纳入反查）"
  puts "  3. 对应任务已被清理，或发文链接与 post_stats.url 不完全一致"
  exit 1
end

group_id = task.group_id
puts "资源任务：#{MODEL_NAMES.fetch(task_model.name, task_model.name)}（#{task_model.name}##{task.id}）"
if group_id.blank?
  puts "该任务 group_id 为空，无法反查同源多平台任务"
  exit 1
end
puts "源视频组 group_id：#{group_id}"

# 资源表视频链接：按注册表 video_field 取（搬运/剪映/花生/Notebooklm 均为 oss_url）
mode = WorkMode.for_model(task_model)
video_field = mode&.video_field || 'oss_url'
video_url = task.respond_to?(video_field) ? task.public_send(video_field) : nil
puts "原视频链接（资源表 #{video_field}）：#{video_url.presence || '（空）'}"

# 搬运任务额外显示更原始的源视频链接（move_video.source_video_url）
if task_model == MoveTask
  src = task.move_video&.source_video_url
  puts "源视频链接（move_video.source_video_url）：#{src.presence || '（空）'}"
end

group_tasks = task_model.where(group_id: group_id).order(:platform)

puts
puts "===== 同源视频各平台发文情况（#{task_model.name}，#{group_tasks.size} 条任务）====="
group_tasks.each do |t|
  acc = t.account
  ps = nil
  if t.account_id.present? && t.actual_publish_time.present?
    ps = PostStat.where(account_id: t.account_id)
                 .where(post_date: t.actual_publish_time.to_date)
                 .order(post_date: :desc)
                 .first
  end
  link = ps&.url || '（未采集到发文链接）'
  acc_name = acc&.account_name || '（账号已删除）'
  mark = (t.id == task.id) ? '  ← 输入链接' : ''
  puts format("%-10s 账号=#%-5s %-24s 状态=%-8s 链接=%s%s",
              t.platform, t.account_id, acc_name, t.status, link, mark)
end
