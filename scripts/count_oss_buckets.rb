# 统计要迁移到 account-agic 的各个源 bucket 的对象数与总大小
# 用法：bundle exec rails runner scripts/count_oss_buckets.rb
require 'aliyun/oss'

MAIN_ID     = ENV['ALIYUN_ACCESS_KEY_ID']
MAIN_SECRET = ENV['ALIYUN_ACCESS_KEY_SECRET']
TWO_ID      = ENV['ALIYUN_ACCESS_TWO_KEY_ID'] || 'gZL8z938T19mSUHf'
TWO_SECRET  = ENV['ALIYUN_ACCESS_TWO_KEY_SECRET'] || 'A9fSDa9cH5YAExpEUR4QSizkFQEcrS'

ENDPOINT = 'https://oss-cn-hangzhou.aliyuncs.com'

BUCKETS = {
  'grok-videos'          => :main,
  'grok-images'          => :main,
  'huasheng-ld-videos'   => :main,
  'huasheng-ld'          => :two,
  'jianying-rd-videos'   => :main,
  'jianying-videos'      => :main,
  'jianying-rd'          => :two,
  'notebooklm-ld-videos' => :main,
  'notebooklm-ld'        => :two,
  'operation-viodes'     => :main,
}.freeze

def client(group)
  id  = group == :two ? TWO_ID : MAIN_ID
  sec = group == :two ? TWO_SECRET : MAIN_SECRET
  Aliyun::OSS::Client.new(endpoint: ENDPOINT, access_key_id: id, access_key_secret: sec)
end

grand_count = 0
grand_bytes = 0

BUCKETS.each do |bucket, group|
  begin
    b = client(group).get_bucket(bucket)
    count = 0
    bytes = 0
    marker = nil
    loop do
      opts = { max_keys: 1000 }
      opts[:marker] = marker if marker
      list = b.list_objects(opts)
      page = list.respond_to?(:objects) ? list.objects : list.to_a
      page.each do |o|
        count += 1
        bytes += (o.respond_to?(:size) ? o.size.to_i : 0)
      end
      marker = list.respond_to?(:next_marker) ? list.next_marker : nil
      break if page.empty? || marker.blank?
    end
    mb = bytes / 1024.0 / 1024.0
    puts "#{bucket}: #{count} 个对象, #{'%.1f' % mb} MB"
    grand_count += count
    grand_bytes += bytes
  rescue => e
    puts "#{bucket}: 统计失败 #{e.class} #{e.message}"
  end
end

gb = grand_bytes / 1024.0 / 1024.0 / 1024.0
puts "----"
puts "总计: #{grand_count} 个对象, #{'%.2f' % gb} GB"
puts "预估流出流量费: 约 #{'%.1f' % (gb * 0.5)} 元（按 0.5 元/GB 粗算）"
