# NotebookLM pending 资源监测脚本：检查视频所在 bucket，旧 bucket 自动迁移。
#
# 背景：
#   NotebooklmTask pending（待分配账号）任务的 oss_url 按新 bucket
#   notebooklm-ld-videos 签名，但生成机器可能仍把视频传到旧 bucket
#   notebooklm-ld（TWO 账号），导致链接 404。
#
# 功能：逐个检查 pending 任务的视频，按视频实际位置分类：
#   [待迁移] 旧 bucket 有、新 bucket 无 → 转存新 bucket + 换链 + 删旧
#   [修链接] 新 bucket 有、旧 bucket 无 → 仅修复仍指向旧 bucket 的链接
#   [两边都有] 旧新都存在 → 修链接（若需）+ 删除旧 bucket 副本
#   [丢失]   两边都没有 → 标记 error_msg 并报告（不删任务）
#
# 特性：幂等可重复执行；默认预览，确认后 EXEC=1 实际执行。
#
# 用法（服务器上执行）：
#   预览： bundle exec rails runner scripts/check_notebooklm_pending_resources.rb
#   执行： EXEC=1 bundle exec rails runner scripts/check_notebooklm_pending_resources.rb

SRC = 'notebooklm-ld'
DST = 'notebooklm-ld-videos'

dst_bucket_client = OssTransfer.oss_client(*OssTransfer.dest_credentials).get_bucket(DST)

pending_scope = NotebooklmTask.pending.where.not(full_oss_url: [nil, ''])
tasks = pending_scope.select(:id, :oss_url, :full_oss_url).to_a
puts "pending 任务：#{tasks.size} 个"

# 按 key 去重检查（同视频多任务只查一次，迁移后统一换链）
by_key = tasks.group_by { |t| t.full_oss_url.to_s.strip.sub(%r{\A/}, '') }

result = Hash.new { |h, k| h[k] = [] }

by_key.each do |key, group|
  in_old = OssTransfer.source_exists?(SRC, key)
  in_new = begin
    dst_bucket_client.object_exists?(key)
  rescue => e
    Rails.logger.warn "[pending检查] 新 bucket 检查失败 #{key}: #{e.message}"
    false
  end

  if in_old && !in_new
    result[:待迁移] << [key, group]
  elsif !in_old && in_new
    result[:修链接] << [key, group]
  elsif in_old && in_new
    result[:两边都有] << [key, group]
  else
    result[:丢失] << [key, group]
  end
end

puts '-' * 60
result.each { |k, v| puts format('%-8s %d 个', k, v.size) }

if ENV['EXEC'] != '1'
  puts '--- 预览模式（确认无误后加 EXEC=1 实际执行）---'
  result[:待迁移].first(20).each { |key, g| puts "  [待迁移] #{key}（#{g.size} 个任务）" }
  result[:修链接].first(10).each { |key, g| puts "  [修链接] #{key}" }
  result[:两边都有].first(10).each { |key, g| puts "  [两边都有] #{key}" }
  result[:丢失].first(10).each { |key, g| puts "  [丢失] #{key}" }
  exit
end

moved = relinked = cleaned = lost = failed = 0

(result[:待迁移] + result[:两边都有]).each do |key, group|
  if result[:待迁移].any? { |k, _| k == key }
    transferred = OssTransfer.transfer(SRC, key)
    unless transferred
      failed += 1
      puts "[失败] #{key}（详见服务端日志 [OssTransfer]）"
      next
    end
    moved += 1
  end

  # 换链：仍指向旧 bucket 签名的任务全部改到新 bucket 签名
  group.each do |t|
    next unless t.oss_url.to_s.include?("#{SRC}.oss-")
    new_url = OssTransfer.dest_sign_url(DST, key)
    NotebooklmTask.where(id: t.id).update_all(oss_url: new_url, full_oss_url: key, updated_at: Time.current)
    relinked += 1
  end

  # 旧 bucket 副本删除
  if OssTransfer.delete_source(SRC, key)
    cleaned += 1
  end
  puts "[处理] #{key}"
end

result[:修链接].each do |key, group|
  group.each do |t|
    next unless t.oss_url.to_s.include?("#{SRC}.oss-")
    new_url = OssTransfer.dest_sign_url(DST, key)
    NotebooklmTask.where(id: t.id).update_all(oss_url: new_url, full_oss_url: key, updated_at: Time.current)
    relinked += 1
  end
  puts "[修链接] #{key}"
end

result[:丢失].each do |key, group|
  ids = group.map(&:id)
  NotebooklmTask.where(id: ids).update_all(
    error_msg: '视频资源缺失（新旧 bucket 均不存在）',
    updated_at: Time.current
  )
  lost += group.size
  puts "[丢失] #{key}（#{group.size} 个任务已标记）"
end

puts '=' * 60
puts "完成：迁移 #{moved}，换链 #{relinked}，删旧副本 #{cleaned}，丢失 #{lost}，失败 #{failed}"
