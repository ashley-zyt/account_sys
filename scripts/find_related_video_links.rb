# -*- coding: utf-8 -*-
# 通过一个最终发文链接，反查「同一个源视频」在其他平台对应的发文链接
#
# 原理：同一个源视频(MoveVideo)剪映完成后，会按平台为每个平台建一条 move_task，
#       这些任务共享同一个 group_id。post_stats.url 没有 group_id，需先通过
#       「账号 + 发文日期」回推到 move_task 拿到 group_id，再反查同组其他平台。
#
# 用法：bundle exec rails runner scripts/find_related_video_links.rb <发文链接>

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
puts "所属账号：##{account.id} #{account.account_name}（平台=#{account.platform}，主题=#{account.theme}）"
puts "发文日期：#{post.post_date}"

# 回推该账号发布此视频的 move_task：优先「账号 + 发文日期当天」匹配，兜底用标题匹配
date = post.post_date
tasks = MoveTask.where(account_id: account.id, status: :success)
                .where(actual_publish_time: date.beginning_of_day..date.end_of_day)
                .order(actual_publish_time: :desc)
if tasks.empty? && post.title.present?
  tasks = MoveTask.where(account_id: account.id, status: :success).where(title: post.title)
end

move_task = tasks.first
unless move_task
  puts "未找到对应的搬运任务（该链接可能不是「视频搬运」产生，或对应任务已被清理）"
  exit 1
end

group_id = move_task.group_id
puts "源视频组 group_id：#{group_id}"

group_tasks = MoveTask.where(group_id: group_id).order(:platform)

puts
puts "===== 同源视频各平台发文情况（#{group_tasks.size} 条任务）====="
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
  mark = (t.id == move_task.id) ? '  ← 输入链接' : ''
  puts format("%-10s 账号=#%-5s %-24s 状态=%-8s 链接=%s%s",
              t.platform, t.account_id, acc_name, t.status, link, mark)
end
