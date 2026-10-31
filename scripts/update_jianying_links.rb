# ===== 更新剪映任务里 oss_url 仍是旧 bucket 的链接为新 bucket =====
#
# 场景：机器端已把视频上传到 jianying-rd-videos，但本项目之前用 jianying-rd 签名，
#       导致这批任务 oss_url 指向旧 bucket。这里用 full_oss_url 重新签名更新。
#
# 用法（生产服务器 Ruby 2.7.2）：
#   bundle exec rails runner scripts/update_jianying_links.rb
#
# 只更新「新 bucket 里确实存在该对象」的任务，避免生成 404 链接。

src  = 'jianying-rd'
dest = 'jianying-rd-videos'
model = JianyingTask

dst_client = OssTransfer.oss_client(*OssTransfer.dest_credentials)
dst_bucket = dst_client.get_bucket(dest)

total = updated = skipped = 0

model.where("oss_url LIKE ?", "%#{src}.oss-%")
     .where.not(full_oss_url: [nil, ''])
     .where("created_at >= ?", 1.hour.ago)
     .find_each do |task|
  total += 1
  key = task.full_oss_url.to_s.strip.sub(%r{^/}, '')

  # 新 bucket 里有这个对象才更新（否则链接会 404）
  unless dst_bucket.object_exists?(key)
    puts "[跳过] ##{task.id} #{key} 新 bucket 无此对象"
    skipped += 1
    next
  end

  new_url = model.oss_v1_sign_url(key)
  if new_url
    task.update_columns(oss_url: new_url, updated_at: Time.current)
    puts "[更新] ##{task.id} #{key}"
    updated += 1
  else
    puts "[失败] ##{task.id} #{key} 签名失败（主账号凭证未配置？）"
  end
end

puts "完成：总计 #{total}，更新 #{updated}，跳过 #{skipped}"
