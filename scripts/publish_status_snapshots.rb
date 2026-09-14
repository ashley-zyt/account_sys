# frozen_string_literal: true

# 查看「发布状况」日报的历史快照（只读，数据来自 storage/publish_status_snapshots/*.json）
#
# 用法：
#   # 最近 14 天快照表格（默认）
#   bundle exec rails runner scripts/publish_status_snapshots.rb
#
#   # 最近 N 天
#   bundle exec rails runner scripts/publish_status_snapshots.rb 30
#
#   # 指定两个日期对比（后者显示与前一天的变化：账号数/发文数）
#   bundle exec rails runner scripts/publish_status_snapshots.rb diff 2026-09-12 2026-09-13
#
# 表格单元格含义：账号数/发文数
#   账号数 = 当日正常状态账号总数（快照值）；发文数 = 当日正常账号发文条数

args = ARGV.dup
mode = args.first

case mode
when 'diff'
  require_date = lambda do |value, label|
    begin
      Date.parse(value.to_s)
    rescue ArgumentError
      puts "#{label} 日期格式无效：#{value.inspect}（应形如 2026-09-13）"
      exit 1
    end
  end

  date_a = require_date.call(args[1], '第一个')
  date_b = require_date.call(args[2], '第二个')

  snap_a = PublishStatusReport.load_snapshot(date_a)
  snap_b = PublishStatusReport.load_snapshot(date_b)

  if snap_a.nil? || snap_b.nil?
    missing = []
    missing << date_a.to_s if snap_a.nil?
    missing << date_b.to_s if snap_b.nil?
    puts "缺少快照：#{missing.join('、')}"
    puts "快照目录：#{PublishStatusReport.snapshot_dir}"
    exit 1
  end

  puts "快照对比（#{date_a} → #{date_b}）"
  puts PublishStatusReport.snapshot_diff_table(snap_a, snap_b)
  puts ""
  puts "注：变化列 = 后一天 − 前一天，格式「账号数变化/发文数变化」"
else
  days = mode.to_s =~ /\A\d+\z/ ? mode.to_i : 14
  snapshots = PublishStatusReport.all_snapshots.last(days)

  if snapshots.empty?
    puts "暂无快照。快照目录：#{PublishStatusReport.snapshot_dir}"
    puts "运行 bundle exec rails runner \"PublishStatusReport.run\" 可生成当日快照"
    exit 0
  end

  puts "发布状况快照（最近 #{snapshots.size} 天，单元格=账号数/发文数）"
  puts PublishStatusReport.snapshot_table(snapshots)
  puts ""
  puts "快照目录：#{PublishStatusReport.snapshot_dir}"
end
