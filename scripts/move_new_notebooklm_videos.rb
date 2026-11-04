# NotebookLM 新视频搬移脚本：旧 bucket（notebooklm-ld）→ 新 bucket（notebooklm-ld-videos）。
#
# 背景：
#   - NotebookLM 生成机器仍把视频上传到旧 bucket notebooklm-ld（TWO 账号）。
#   - 但 NotebooklmTask 建任务时已按新 bucket 签名（OSS_BUCKET=notebooklm-ld-videos，
#     主账号 ENV 凭证），视频不在新 bucket 时链接会 404。
#   - 本脚本把视频从旧 bucket 搬到新 bucket（同 key），让任务链接生效，
#     并更新仍指向旧 bucket 的任务链接、删除旧 bucket 源文件。
#
# 特性：
#   - 幂等：新 bucket 已存在同名对象则跳过搬移（可重复执行）。
#   - 去重：同一视频被多个任务/关键词引用时只搬一次。
#   - 默认预览模式，确认列表无误后加 EXEC=1 实际执行。
#
# 用法（服务器上执行）：
#   预览： bundle exec rails runner scripts/move_new_notebooklm_videos.rb [起始日期]
#   执行： EXEC=1 bundle exec rails runner scripts/move_new_notebooklm_videos.rb [起始日期]
#   起始日期可选（如 2026-11-03，含当天起），不传则处理全部记录。

require 'json'

SRC = 'notebooklm-ld'

since = ARGV[0].presence ? Date.parse(ARGV[0]).beginning_of_day : nil

keys = []

# 1) 资源队列任务里登记的 object key
task_scope = NotebooklmTask.where.not(full_oss_url: [nil, ''])
task_scope = task_scope.where('created_at >= ?', since) if since
keys += task_scope.pluck(:full_oss_url).map { |k| k.to_s.strip.sub(%r{\A/}, '') }

# 2) 已完成关键词 result_data 里的 oss_url（object key），覆盖尚未生成任务的关键词
kw_scope = NotebooklmKeyword.where(status: 3).where.not(result_data: [nil, ''])
kw_scope = kw_scope.where('updated_at >= ?', since) if since
kw_scope.find_each do |kw|
  result = (JSON.parse(kw.result_data) rescue nil) || next
  key = result['oss_url'].to_s.strip.sub(%r{\A/}, '')
  keys << key if key.present?
end

keys = keys.uniq.reject(&:blank?)
puts "待检查唯一视频：#{keys.size} 个#{since ? "（#{since.to_date} 起）" : ''}"

if ENV['EXEC'] != '1'
  puts '--- 预览模式（确认无误后加 EXEC=1 实际执行）---'
  keys.first(30).each { |k| puts "  #{k}" }
  puts "  ... 共 #{keys.size} 个" if keys.size > 30
  exit
end

moved = skipped = failed = 0
keys.each do |key|
  # 源已不存在：可能早已搬过或被清理，跳过（新 bucket 已存在时 transfer 幂等返回签名）
  unless OssTransfer.source_exists?(SRC, key)
    skipped += 1
    next
  end

  transferred = OssTransfer.transfer(SRC, key)
  if transferred
    new_key, new_url = transferred

    # 更新仍指向旧 bucket 的任务链接（full_oss_url 相同的所有任务）
    cnt = NotebooklmTask.where("oss_url LIKE ?", "%#{SRC}.oss-%")
                        .where(full_oss_url: [key, "/#{key}"])
                        .update_all(oss_url: new_url, full_oss_url: new_key, updated_at: Time.current)

    OssTransfer.delete_source(SRC, key)
    moved += 1
    puts "[成功] #{key}（更新 #{cnt} 条任务链接）"
  else
    failed += 1
    puts "[失败] #{key}（详见服务端日志 [OssTransfer]）"
  end
end

puts "完成：搬移 #{moved}，源缺失跳过 #{skipped}，失败 #{failed}"
