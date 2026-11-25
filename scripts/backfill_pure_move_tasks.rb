# encoding: UTF-8
# ============================================================
# 补建纯搬运资源队列：扫描所有「已下载」的纯搬运主题视频，
# 确保它们都有对应的 PureMoveTask（幂等）。
#
# 用法（在项目根目录运行）：
#   RAILS_ENV=production ruby scripts/backfill_pure_move_tasks.rb
# ============================================================
require_relative "../config/environment"

result = MoveVideo.backfill_pure_move_tasks!

puts "扫描已下载纯搬运视频：#{result[:scanned]} 条"
puts "新建 PureMoveTask：#{result[:created]} 条"
