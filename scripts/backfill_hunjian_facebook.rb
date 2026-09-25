# ===== 给搬运混剪队列补 facebook 平台记录（preview / confirm 两阶段）=====
#
# 背景：搬运混剪成品按 platforms 建多条 HunjianTask（每平台一条），
#       历史上部分成品漏建了 facebook。本脚本给缺 facebook 的成品组各补一条。
#
# 分组依据：group_id（同一混剪成品的多平台任务共享，见 hunjian_tasks 表注释）
#
# 用法：
#   预览（只扫描，不建任何记录）：
#     bundle exec rails runner scripts/backfill_hunjian_facebook.rb
#   执行（真正补建）：
#     bundle exec rails runner scripts/backfill_hunjian_facebook.rb confirm

# 取 facebook 标题：facebook 用「长标题」（含话题）。
# 同组非 youtube 记录 title 即长标题；只有 youtube 时其 description 才是长标题（youtube 交换存）。
def title_for_facebook(records)
  non_yt = records.find { |r| r.platform != 'youtube' }
  return non_yt.title if non_yt

  yt = records.find { |r| r.platform == 'youtube' }
  yt&.description.presence || yt&.title
end

confirm = (ARGV[0] == 'confirm')

# 1. 按 group_id 分组（排除 group_id 空的脏数据）
groups = HunjianTask.where.not(group_id: [nil, '']).order(:id).group_by(&:group_id)

# 2. 找出缺 facebook 的成品组
missing = []
groups.each do |gid, records|
  next if records.any? { |r| r.platform == 'facebook' }
  missing << [gid, records]
end

puts "==== #{confirm ? '执行' : '预览'}：补 facebook 混剪任务 ===="
puts "混剪成品组 #{groups.size} 组，缺 facebook 的 #{missing.size} 组"
puts

# 3. 预览清单
missing.each do |gid, records|
  template = records.first
  puts "  组 #{gid}：move_video_ids=#{template.move_video_ids} | theme=#{template.theme} | 现有平台=#{records.map(&:platform).join('/')}"
end

# 4. confirm 补建
if confirm
  created = 0
  skipped = 0
  missing.each do |gid, records|
    # 幂等：创建前再查一次，防止重复跑
    if HunjianTask.exists?(group_id: gid, platform: :facebook)
      skipped += 1
      next
    end

    template = records.first
    title = title_for_facebook(records)

    HunjianTask.create!(
      move_video_ids: template.move_video_ids,
      oss_url: template.oss_url,
      full_oss_url: template.full_oss_url,
      title: title,
      description: nil,          # facebook 不存描述（与 create_from_hunjian_result! 一致）
      platform: :facebook,
      theme: template.theme,
      group_id: gid,
      status: :pending
    )
    created += 1
  end
  puts
  puts "✅ 补建 #{created} 条 facebook 记录" + (skipped > 0 ? "，#{skipped} 组已存在跳过" : "")
elsif missing.empty?
  puts "无需补建，所有组都已有 facebook 记录。"
else
  puts
  puts "⚠️ 以上为预览，未建任何记录。确认后执行："
  puts "  bundle exec rails runner scripts/backfill_hunjian_facebook.rb confirm"
end
