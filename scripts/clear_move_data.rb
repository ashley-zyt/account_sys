# -*- coding: utf-8 -*-
# ============================================================
# 清除所有搬运视频储备（move_videos）+ 搬运资源队列未执行/执行中任务（move_tasks）
# 并同步删除这些记录对应的 OSS 文件
# ============================================================
# 用法：
#   bundle exec rails runner scripts/clear_move_data.rb            # 预览（只统计，不改数据）
#   bundle exec rails runner scripts/clear_move_data.rb confirm    # 执行
#
# 清除范围：
#   move_videos : 全部删除
#   move_tasks  : 删除 pending / waiting_publish / executing（保留 success / failed 历史）
#
# OSS 同步删除：
#   - move_videos.raw_oss_url          （原始视频，jianying-videos bucket）
#   - move_tasks.oss_url               （剪映成片，仅删 pending/waiting_publish/executing 的）
#   bucket 名从 URL host 自动解析（xxx.oss-cn-hangzhou.aliyuncs.com → xxx），无需硬编码。
#   ⚠️ 去重后删除，且排除「保留的 success/failed 任务仍在引用」的成片 URL，避免误删。
#
# 不影响其他表（account / browser / task_log / browser_task_record 均不动）。
#
# ⚠️ 提醒：executing 任务机器端可能还在跑（goroutine）。本脚本只清 account_sys 本地，
#   不中断机器端。若需一并中断，先跑 scripts/cancel_executing_tasks.rb（按平台）或调
#   机器端 POST /tasks/clear?type={platform}_publish&status=running,queued。
# ============================================================

require 'uri'

OSS_ENDPOINT   = 'https://oss-cn-hangzhou.aliyuncs.com'.freeze
DELETE_STATUSES = [:pending, :waiting_publish, :executing].freeze
KEEP_STATUSES   = [:success, :failed].freeze

confirm = ARGV[0] == 'confirm'

# 从 OSS URL 解析 bucket 与 key（兼容签名 URL，query 参数被忽略）
def parse_oss_url(url)
  uri = URI.parse(url.to_s)
  bucket = uri.host.to_s.split('.').first
  key = uri.path.to_s.sub(%r{\A/}, '')
  begin
    key = URI.decode_www_form_component(key)
  rescue StandardError
    # 解码失败则用原始 path
  end
  [bucket, key]
end

# 懒加载 OSS client（复用，避免每个文件新建）
def oss_client
  $oss_client ||= begin
    require 'aliyun/oss'
    Aliyun::OSS::Client.new(
      endpoint: OSS_ENDPOINT,
      access_key_id: ENV['ALIYUN_ACCESS_KEY_ID'],
      access_key_secret: ENV['ALIYUN_ACCESS_KEY_SECRET']
    )
  end
end

# 删除单个 OSS 对象，返回 [结果, 消息]；404 视为「已不存在」算成功
def delete_one_oss(url)
  return [:skip, 'URL 为空'] if url.blank?

  bucket, key = parse_oss_url(url)
  return [:fail, "无法解析 bucket/key: #{url[0, 80]}"] if bucket.blank? || key.blank?

  oss_client.get_bucket(bucket).delete_object(key)
  [:ok, nil]
rescue => e
  msg = e.message.to_s
  if msg.include?('404') || msg.include?('NoSuchKey') || msg.include?('NoSuchFile')
    [:ok, '对象已不存在']
  else
    [:fail, msg]
  end
end

# 收集要删除的 OSS URL（去重 + 排除保留任务仍引用的）
def collect_oss_urls
  keep_urls = MoveTask.where(status: KEEP_STATUSES)
                      .where.not(oss_url: nil)
                      .pluck(:oss_url).compact.map(&:to_s).uniq

  urls = []
  urls += MoveVideo.where.not(raw_oss_url: nil).pluck(:raw_oss_url)
  # 成片 URL 已迁移到 move_tasks.oss_url（move_videos 已无 processed_oss_url 字段）
  urls += MoveTask.where(status: DELETE_STATUSES).where.not(oss_url: nil).pluck(:oss_url)
  urls = urls.compact.map(&:to_s).uniq
  urls -= keep_urls
  urls
end

videos_total = MoveVideo.count
tasks_total  = MoveTask.count
delete_count = MoveTask.where(status: DELETE_STATUSES).count
keep_count   = MoveTask.where(status: KEEP_STATUSES).count
oss_urls     = collect_oss_urls

puts "===== 搬运数据清除 + OSS 同步删除（#{confirm ? '执行' : '预览'}）====="
puts ""
puts "move_videos 总计 : #{videos_total} 条（全部删除）"
puts "move_tasks  总计 : #{tasks_total} 条"
puts ""
puts "move_tasks 按状态分布："
MoveTask.statuses.keys.each do |s|
  c = MoveTask.where(status: s).count
  mark = DELETE_STATUSES.include?(s.to_sym) ? ' → 删除' : ' → 保留'
  puts format("  %-18s %d 条%s", s, c, mark)
end
puts ""
puts "将删除 move_tasks : #{delete_count} 条（pending/waiting_publish/executing）"
puts "将保留 move_tasks : #{keep_count} 条（success/failed 历史）"
puts "将删除 move_videos: #{videos_total} 条"
puts "将删除 OSS 文件   : #{oss_urls.size} 个（raw + 成片，去重后，已排除保留任务仍引用的）"

unless confirm
  puts ""
  puts "这是预览，未做任何修改。确认无误后执行："
  puts "  bundle exec rails runner scripts/clear_move_data.rb confirm"
  exit
end

puts ""
puts "===== 开始执行 ====="

# ① 删除未执行/执行中的 move_tasks
n1 = MoveTask.where(status: DELETE_STATUSES).delete_all
puts "① 已删除 move_tasks（pending/waiting_publish/executing）：#{n1} 条"

# ② 断开剩余 move_tasks 对 move_videos 的引用（move_videos 即将全删）
n2 = MoveTask.update_all(move_video_id: nil)
puts "② 已将剩余 #{n2} 条 move_tasks 的 move_video_id 置空"

# ③ 删除全部 move_videos
n3 = MoveVideo.delete_all
puts "③ 已删除 move_videos：#{n3} 条"

# ④ 删除 OSS 文件（用删除前收集的 URL，容错）
puts "④ 开始删除 OSS 文件（共 #{oss_urls.size} 个）..."
if ENV['ALIYUN_ACCESS_KEY_ID'].blank? || ENV['ALIYUN_ACCESS_KEY_SECRET'].blank?
  puts "   ⚠️ 未配置 ALIYUN_ACCESS_KEY_ID / ALIYUN_ACCESS_KEY_SECRET，跳过 OSS 删除"
else
  ok = fail = skip = 0
  oss_urls.each_with_index do |url, i|
    res, msg = delete_one_oss(url)
    case res
    when :ok   then ok += 1
    when :skip then skip += 1
    when :fail
      fail += 1
      puts "   失败 #{url[0, 80]}: #{msg}"
    end
    puts "   进度 #{i + 1}/#{oss_urls.size}" if ((i + 1) % 100).zero?
  end
  puts "   OSS 删除完成：成功 #{ok}，失败 #{fail}，跳过 #{skip}"
end

puts ""
puts "===== 完成 ====="
puts "搬运数据已清除。account / browser / task_log / browser_task_record 均未改动。"
