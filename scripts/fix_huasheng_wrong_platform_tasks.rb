# frozen_string_literal: true
# ============================================================
# 修复错误生成的花生资源队列任务（huasheng_tasks）
# ============================================================
# 背景：旧版 HuashengTask.create_from_huasheng_keyword! 用
#   keyword.include?("|") 判断平台，导致「非抖音号视频号主题」的关键词
#   错误生成了 platform=抖音-视频号 的单条任务。
# 修复：找出这些错误任务 → 删除 → 按新规则（常规主题 → 海外 5 平台各一条）
#   重新入库。
#
# 用法：
#   bundle exec rails runner scripts/fix_huasheng_wrong_platform_tasks.rb            # 预览（只统计）
#   bundle exec rails runner scripts/fix_huasheng_wrong_platform_tasks.rb confirm    # 执行
#
# 安全说明：
#   - 只处理 platform=抖音-视频号 且 theme != 花生视频-抖音号视频号 的任务，
#     正确主题（抖音号视频号）的任务一律不动。
#   - 重新入库失败（关键词未完成 / 缺 oss_url）时会把 pushed 置 false，
#     交由 HuashengQueueScheduler 每小时兜底重推，不会静默丢数据。
# ============================================================

require 'benchmark'

confirm = ARGV[0] == 'confirm'

THEME_KEY    = HuashengTask::DOUYIN_SHIPINHAO_THEME
PLATFORM_KEY = "抖音-视频号".freeze

# 找出错误任务：platform=抖音-视频号 且 theme != 花生视频-抖音号视频号
wrong_scope = HuashengTask.where(platform: HuashengTask.platforms[PLATFORM_KEY])
                          .where.not(theme: THEME_KEY)

wrong_count = wrong_scope.count
keyword_ids = wrong_scope.distinct.pluck(:huasheng_keyword_id).compact.uniq

puts "===== 修复错误花生资源队列任务（#{confirm ? '执行' : '预览'}）====="
puts "条件：platform=#{PLATFORM_KEY} 且 theme != #{THEME_KEY}"
puts "错误任务：#{wrong_count} 条"
puts "涉及关键词：#{keyword_ids.size} 个"
puts ""

puts "---- 按主题分布 ----"
wrong_scope.group(:theme).count.sort_by { |_, n| -n }.each do |theme, n|
  puts "  #{theme || '(空主题)'}：#{n} 条"
end

unless confirm
  puts ""
  puts "---- 错误任务明细（前 50 条）----"
  wrong_scope.order(:id).limit(50).pluck(:id, :huasheng_keyword_id, :theme, :status).each do |id, kid, theme, status|
    puts "  任务 #{id}  keyword_id=#{kid}  theme=#{theme}  status=#{status}"
  end
  puts ""
  puts "这是预览，未做任何修改。确认后执行："
  puts "  bundle exec rails runner scripts/fix_huasheng_wrong_platform_tasks.rb confirm"
  exit
end

puts ""
puts "===== 开始执行 ====="

deleted    = 0
regen_ok   = 0
regen_fail = 0
regen_skip = 0

time = Benchmark.measure do
  # ① 删除错误任务本身（正确主题的任务不动）
  deleted = wrong_scope.delete_all
  puts "① 已删除错误任务 #{deleted} 条"

  # ② 逐个关键词：无剩余任务则按新规则重新入库
  puts "② 开始重新入库..."
  keyword_ids.each do |kid|
    kw = HuashengKeyword.find_by(id: kid)
    if kw.nil?
      regen_skip += 1
      puts "  keyword #{kid} 已不存在，跳过"
      next
    end

    # 该关键词下若还有其它任务（数据异常时），保留原样，不重建
    if HuashengTask.where(huasheng_keyword_id: kid).exists?
      regen_skip += 1
      puts "  keyword #{kid}（#{kw.theme}）仍有剩余任务，跳过重建"
      next
    end

    created, err = HuashengTask.create_from_huasheng_keyword!(kw)
    if created > 0
      regen_ok += 1
      kw.update!(pushed: true)
      puts "  keyword #{kid}（#{kw.theme}）重新入库 #{created} 条 ✓"
    else
      regen_fail += 1
      # 失败则 pushed 置 false，交由 HuashengQueueScheduler 每小时兜底重推
      kw.update!(pushed: false)
      puts "  keyword #{kid}（#{kw.theme}）重新入库失败：#{err}（已置 pushed=false 交定时任务兜底）"
    end
  end
end

puts ""
puts "===== 完成 ====="
puts "删除错误任务：#{deleted} 条"
puts "重新入库成功：#{regen_ok} 个关键词"
puts "重新入库失败：#{regen_fail} 个关键词（已置 pushed=false 兜底）"
puts "跳过：#{regen_skip} 个关键词（已不存在或仍有剩余任务）"
puts "耗时：#{time.real.round(2)} 秒"
