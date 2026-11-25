# encoding: UTF-8
# ============================================================
# 对标账号储备入库（批量）：读取 source.txt 的内容，直接在项目内解析
# 视频链接+标题批量入库（不再走 HTTP 接口，避免大 HTML 传参问题）。
#
# 用法（在项目根目录运行）：
#   RAILS_ENV=production ruby import_videos.rb
# ============================================================
require_relative "config/environment"
require "cgi"

SOURCE_URL    = "https://www.douyin.com/user/MS4wLjABAAAAPZNmFroK5J0Q9O-H_yooQl_n6sx7jqghMtvncZIDxsX9KdTQp6DsFKZQDgpTbYvS?from_tab_name=main&vid=7644151715096218233"  # ← 改成实际对标账号主页链接
HTML_FILE_PATH = Rails.root.join("source.txt")

unless File.exist?(HTML_FILE_PATH)
  puts "❌ 找不到文件 #{HTML_FILE_PATH}"
  exit
end

html = File.read(HTML_FILE_PATH, encoding: "UTF-8", invalid: :replace, undef: :replace)
puts "正在批量导入，source.txt 大小 #{html.bytesize} 字节..."

result = MoveVideo.import_from_html!(source_url: SOURCE_URL, html: html)

puts "匹配主题：#{result[:themes].join(', ')}"
puts "预期入库：#{result[:total]} 条（视频数 × 主题数）"
puts "新建：#{result[:created]} 条"
puts "已存在跳过：#{result[:skipped]} 条"
