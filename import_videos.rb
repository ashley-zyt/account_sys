# encoding: UTF-8
# ============================================================
# 对标账号储备入库（批量）：读取 source.txt 的内容，一次性 POST 到
# move_videos/import 接口，由接口解析视频链接+标题批量入库。
#
# 用法：
#   1. 把对标账号主页链接填到下面的 SOURCE_URL
#   2. 复制对标账号的视频列表源代码到 /mnt/account_sys/source.txt
#   3. 运行：ruby import_videos.rb
# ============================================================
require "uri"
require "net/http"

SOURCE_URL    = "https://www.douyin.com/user/改成实际的对标账号ID"  # ← 改成实际对标账号主页链接
HTML_FILE_PATH = "/mnt/account_sys/source.txt"
API_BASE      = "http://47.89.235.227:3366/api/v1/move_videos/import"

unless File.exist?(HTML_FILE_PATH)
  puts "❌ 找不到文件 #{HTML_FILE_PATH}"
  exit
end

html = File.read(HTML_FILE_PATH, encoding: "UTF-8", invalid: :replace, undef: :replace)
puts "正在批量导入，source.txt 大小 #{html.bytesize} 字节..."

uri = URI(API_BASE)
http = Net::HTTP.new(uri.host, uri.port)
http.open_timeout = 30
http.read_timeout = 120

request = Net::HTTP::Post.new(uri)
request.set_form_data(source_url: SOURCE_URL, html: html)

response = http.request(request)
puts "HTTP #{response.code}"
puts response.body.to_s.force_encoding('UTF-8')
