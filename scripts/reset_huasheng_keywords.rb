# frozen_string_literal: true

# 批量重置花生视频储备关键词状态为"未启动"(status=0)
# 对于已完成(status=3)的记录，会同时删除对应的 OSS 文件
# 执行: rails runner scripts/reset_huasheng_keywords.rb
#
# 使用方式:
#   1. 编辑下面的 ids 数组，指定要重置的关键词 ID
#   2. 运行: rails runner scripts/reset_huasheng_keywords.rb
#   3. 确认后执行

require 'benchmark'
require 'aliyun/oss'

# OSS 配置
OSS_BUCKET = "huasheng-ld".freeze
OSS_REGION = "cn-hangzhou".freeze
OSS_ENDPOINT = "https://oss-#{OSS_REGION}.aliyuncs.com".freeze
OSS_ACCESS_KEY_ID = "gZL8z938T19mSUHf".freeze
OSS_ACCESS_KEY_SECRET = "A9fSDa9cH5YAExpEUR4QSizkFQEcrS".freeze

def delete_oss_file(oss_url)
  return false if oss_url.blank?

  client = Aliyun::OSS::Client.new(
    endpoint: OSS_ENDPOINT,
    access_key_id: OSS_ACCESS_KEY_ID,
    access_key_secret: OSS_ACCESS_KEY_SECRET
  )
  bucket = client.get_bucket(OSS_BUCKET)
  bucket.delete_object(oss_url)
  true
rescue => e
  puts "  [WARN] 删除 OSS 文件失败: #{oss_url} - #{e.message}"
  false
end

puts "=" * 60
puts "批量重置花生视频储备关键词状态脚本"
puts "=" * 60

# 在此处指定要重置的 ID 列表
ids = [326,325,315,321]

if ids.empty?
  puts "请在脚本中指定要重置的 ID 列表"
  puts "例如: ids = [1, 2, 3]"
  exit 1
end

count = HuashengKeyword.where(id: ids).count
puts "ID 列表: #{ids}"
puts "范围内记录数: #{count}"

if count == 0
  puts "没有需要更新的数据，脚本退出"
  exit 0
end

# 检查并删除已完成记录的 OSS 文件
completed_records = HuashengKeyword.where(id: ids, status: 3)
if completed_records.any?
  puts ""
  puts "检测到 #{completed_records.count} 条已完成记录，将删除对应的 OSS 文件:"
  completed_records.each do |record|
    result = (JSON.parse(record.result_data) rescue {})
    oss_url = result["oss_url"].to_s.strip
    if oss_url.present?
      puts "  ID=#{record.id} key=#{record.keyword}: 删除 OSS 文件 #{oss_url}"
      delete_oss_file(oss_url)
    else
      puts "  ID=#{record.id} key=#{record.keyword}: result_data 中无 oss_url，跳过"
    end
  end
end

print "确认将以上 #{count} 条数据的状态更新为未启动？(y/N): "
answer = STDIN.gets&.strip
unless answer&.downcase == 'y'
  puts "已取消操作"
  exit 0
end

time = Benchmark.measure do
  updated = HuashengKeyword.where(id: ids).update_all(
    status: 0,
    task_id: nil,
    result_data: nil,
    pushed: false,
    updated_at: Time.current
  )
  puts "成功更新 #{updated} 条记录"
end

puts "耗时: #{time.real.round(2)} 秒"

puts "=" * 60
puts "重置完成！"
puts "=" * 60
