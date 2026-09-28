# 只读预览：搬运源视频下载优先级（不 claim、不改任何数据）
#
# 用法：
#   bundle exec rails runner scripts/preview_download_order.rb          # 默认模拟连续领 100 条
#   bundle exec rails runner scripts/preview_download_order.rb 200      # 自定义模拟条数
#
# 输出两块：
#   1) 当前各「待下载」主题的可用天数明细（按优先级降序 = 最缺在前）
#   2) 内存推演：模拟连续领取 N 条，看实际会按什么顺序、各主题各领几条
# 推演完全在内存里做（不改库），用与 MoveVideo.source_availability_days 相同的口径。

simulate_n = (ARGV[0] || 100).to_i

themes = MoveVideo.pending_download.where.not(theme: [nil, '']).distinct.pluck(:theme)

if themes.empty?
  puts "当前没有任何「待下载」的源视频，无需排序。"
  exit
end

# 各主题「待下载」数（真正能被下载软件领走的总量）
pending_counts = MoveVideo.pending_download.where(theme: themes).group(:theme).count

# 各主题「源视频储备」数（与 source_availability_days 同口径：待下载+下载中+已下载未双完成）
stock = MoveVideo.where(theme: themes)
                 .where(
                   "status IN (?) OR (status = ? AND NOT (jianying_status = ? AND hunjian_status = ?))",
                   [MoveVideo.statuses[:pending_download], MoveVideo.statuses[:downloading]],
                   MoveVideo.statuses[:downloaded],
                   MoveVideo.jianying_statuses[:completed],
                   MoveVideo.hunjian_statuses[:completed]
                 )
                 .group(:theme).count

# 各主题正常账号数（搬运剪映 + 搬运混剪）
accounts = Account.active
                 .where(work_type: %w[搬运剪映 搬运混剪], theme: themes)
                 .group(:theme).count

days = MoveVideo.source_availability_days(themes)

puts "=" * 78
puts "一、当前各待下载主题 可用天数明细（越靠前 = 越缺 = 越优先下载）"
puts "=" * 78
rows = themes.map do |t|
  a = accounts[t].to_i
  s = stock[t].to_i
  p = pending_counts[t].to_i
  d = days[t].to_f
  [d, t, s, p, a]
end.sort_by { |r| [r[0], r[1]] }

puts format("  %-9s %-6s %-6s %-6s %s", "可用天数", "储备", "待下载", "账号", "主题")
puts "  " + "-" * 66
rows.each do |d, t, s, p, a|
  puts format("  %-9s %-6d %-6d %-6d %s",
              d.zero? ? "0.0(缺)" : format("%.1f 天", d), s, p, a, t)
end

puts
puts "=" * 78
puts "二、模拟连续领取 #{simulate_n} 条的顺序（纯内存推演，不改库）"
puts "=" * 78

sim_pending = pending_counts.dup
sim_stock   = stock.dup
order = []

simulate_n.times do
  cands = sim_pending.select { |_t, c| c > 0 }.keys
  break if cands.empty?

  chosen = cands.min_by do |t|
    a = accounts[t].to_i
    d = a > 0 ? sim_stock[t].to_f / a : 0.0
    [d, t]
  end

  order << chosen
  sim_pending[chosen] -= 1
  sim_stock[chosen] -= 1 if sim_stock[chosen].to_i > 0
end

if order.empty?
  puts "  无可领取（待下载数全为 0）"
else
  tally = order.each_with_object(Hash.new(0)) { |t, h| h[t] += 1 }

  if order.size <= 60
    puts "  领取顺序："
    order.each_with_index { |t, i| puts format("    %3d. %s", i + 1, t) }
  else
    puts "  领取顺序（仅展示前 60 条，共 #{order.size} 条）："
    order.first(60).each_with_index { |t, i| puts format("    %3d. %s", i + 1, t) }
    puts "    ..."
  end

  puts
  puts "  各主题实际领取条数统计："
  tally.sort_by { |t, c| [-c, t] }.each do |t, c|
    puts format("    %-20s %d 条", t, c)
  end
end

puts
puts "说明："
puts "  - 可用天数 = 源视频储备 / 正常账号数；无账号的主题记 0（最缺、最先下载）。"
puts "  - 推演中每领走一条，该主题储备减 1，可用天数随之上升，追平后开始轮转到下一主题。"
puts "  - 真实下载软件每次 GET /api/v1/move_videos/fetch_for_download 领一条，顺序与本推演一致。"
