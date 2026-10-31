# ===== 列出源/目标 bucket 对象，确认 key 格式 =====
#
# 用法（生产服务器 Ruby 2.7.2）：
#   bundle exec rails runner scripts/list_oss_buckets.rb
#
# 目的：核对源 bucket 里的实际对象 key 是否与库里 full_oss_url 一致。

def list_bucket(client, bucket, label, limit: 30)
  puts "---- #{label} (#{bucket}) ----"
  begin
    b = client.get_bucket(bucket)
    list = b.list_objects(max_keys: limit)
    page = list.respond_to?(:objects) ? list.objects : list.to_a
    if page.empty?
      puts "  （空）"
    else
      page.each { |o| puts "  #{o.key}" }
    end
  rescue => e
    puts "  ❌ #{e.class}: #{e.message[0, 120]}"
  end
  puts
end

src_client = OssTransfer.oss_client(*OssTransfer.source_credentials)
dst_client = OssTransfer.oss_client(*OssTransfer.dest_credentials)

puts "===== 源 bucket（TWO 账号）====="
list_bucket(src_client, 'huasheng-ld',   'huasheng-ld')
list_bucket(src_client, 'jianying-rd',   'jianying-rd')
list_bucket(src_client, 'notebooklm-ld', 'notebooklm-ld')

puts "===== 目标 bucket（主账号）====="
list_bucket(dst_client, 'huasheng-ld-videos',   'huasheng-ld-videos')
list_bucket(dst_client, 'jianying-rd-videos',   'jianying-rd-videos')
list_bucket(dst_client, 'notebooklm-ld-videos', 'notebooklm-ld-videos')

puts "===== 库里 full_oss_url 样例（各取 3 条）====="
[['HuashengTask', 'huasheng-ld'], ['JianyingTask', 'jianying-rd'], ['NotebooklmTask', 'notebooklm-ld']].each do |name, _src|
  model = name.constantize
  keys = model.where.not(full_oss_url: [nil, '']).order(id: :asc).limit(3).pluck(:id, :full_oss_url)
  puts "---- #{name} ----"
  keys.each { |id, k| puts "  ##{id} #{k}" }
  puts
end
