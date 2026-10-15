# ===== 回填混剪任务标题（中文 → 英文重生成后更新）=====
#
# 背景：deepseek 崩溃导致混剪平台当日生成的标题部分为中文，现已重新生成英文版。
#       用「重生成标题对照表.xlsx」把尚未发布的混剪任务的标题/描述更新为英文。
#
# 匹配方式：Excel 每行的 video_id + partner_id = 混剪的两个源视频 move_video.id，
#           对应 hunjian_task.move_video_ids（逗号分隔的两个源视频 id，顺序无关）。
#
# 更新规则（与 HunjianTask.create_from_hunjian_result! 存储约定一致）：
#   - YouTube 平台：title ← 新描述，description ← 新标题（YouTube 标题限长，长标题存 description）
#   - 其它平台  ：title ← 新标题，description 不变
#   - 仅更新「尚未成功发布」的任务（status != success），已发布的不动
#
# 用法（服务器上，项目根目录）：
#   预览（只扫描+统计，不改任何数据）：
#     bundle exec rails runner scripts/update_hunjian_retitles.rb /path/to/重生成标题对照表_final.xlsx
#   执行（真正更新）：
#     bundle exec rails runner scripts/update_hunjian_retitles.rb /path/to/重生成标题对照表_final.xlsx confirm

require 'roo'

xlsx_path = ARGV[0]
confirm  = (ARGV[1] == 'confirm')

unless xlsx_path && File.exist?(xlsx_path)
  puts "用法: bundle exec rails runner scripts/update_hunjian_retitles.rb <xlsx路径> [confirm]"
  puts "  <xlsx路径>  重生成标题对照表.xlsx 的绝对路径"
  puts "  confirm     可选，带上才真正执行更新；不带只预览"
  exit 1
end

# ---- 1. 读 Excel ----
xlsx  = Roo::Spreadsheet.open(xlsx_path)
sheet = xlsx.sheet(0)

rows = []
(2..sheet.last_row).each do |i|
  raw_vid = sheet.cell(i, 1)
  raw_pid = sheet.cell(i, 2)
  next if raw_vid.nil? || raw_pid.nil?

  rows << {
    video_id:  raw_vid.to_i,
    partner_id: raw_pid.to_i,
    theme:      sheet.cell(i, 3).to_s.strip,
    new_title:  sheet.cell(i, 5).to_s.strip,
    new_desc:   sheet.cell(i, 6).to_s.strip
  }
end

puts "==== #{confirm ? '执行' : '预览'}：回填混剪英文标题 ===="
puts "Excel 数据 #{rows.size} 行"
puts

# ---- 2. 用 FIND_IN_SET 粗筛 move_video_ids 含任一源视频 id 的混剪任务 ----
all_ids = rows.flat_map { |r| [r[:video_id], r[:partner_id]] }.uniq
id_strs = all_ids.map(&:to_s)
tasks = if id_strs.empty?
          HunjianTask.none
        else
          conds = id_strs.map { 'FIND_IN_SET(?, move_video_ids) > 0' }.join(' OR ')
          HunjianTask.where(conds, *id_strs).to_a
        end

puts "粗筛到候选混剪任务 #{tasks.size} 条"
puts

# ---- 3. 精确匹配：move_video_ids 同时包含 video_id 与 partner_id ----
parse_ids = ->(t) { t.move_video_ids.to_s.split(',').map(&:strip).map(&:to_i) }

rows.each do |row|
  vid = row[:video_id]
  pid = row[:partner_id]
  row[:tasks] = tasks.select { |t| (parse_ids.call(t) & [vid, pid]).size == 2 }
end

matched_rows  = rows.select { |r| r[:tasks].any? }
unmatched_rows = rows.select { |r| r[:tasks].empty? }

puts "精确匹配：命中 #{matched_rows.size} 行 / 未命中 #{unmatched_rows.size} 行"
puts

# ---- 4. 未命中明细 ----
unless unmatched_rows.empty?
  puts "==== 未命中行（video_id + partner_id 匹配不到任何 hunjian_task）===="
  unmatched_rows.each do |r|
    puts "  video_id=#{r[:video_id]} partner_id=#{r[:partner_id]} theme=#{r[:theme]}"
  end
  puts
end

# ---- 5. 命中行的任务状态分布 & 待更新清单 ----
if matched_rows.any?
  all_matched = matched_rows.flat_map { |r| r[:tasks] }
  status_dist = all_matched.group_by(&:status).transform_values(&:size)
  puts "命中任务状态分布：#{status_dist.map { |s, c| "#{s}=#{c}" }.join('  ')}"
  puts

  to_update = all_matched.reject(&:success?)
  skip_success = all_matched.count(&:success?)
  puts "待更新（status != success）: #{to_update.size} 条；已发布跳过: #{skip_success} 条"
  puts
end

# ---- 6. 预览：逐行展示将更新的任务 ----
if matched_rows.any? && !confirm
  puts "==== 预览明细（前 30 行）===="
  matched_rows.first(30).each do |r|
    r[:tasks].each do |t|
      next if t.success?
      new_title = t.platform == 'youtube' ? r[:new_desc] : r[:new_title]
      puts "  行 video_id=#{r[:video_id]}/#{r[:partner_id]} → task##{t.id} platform=#{t.platform} status=#{t.status}"
      puts "    旧 title: #{t.title.to_s.truncate(60)}"
      puts "    新 title: #{new_title.to_s.truncate(60)}"
    end
  end
  puts
end

# ---- 7. 执行更新 ----
if confirm
  updated = 0
  skipped = 0
  errors = 0

  rows.each do |r|
    r[:tasks].each do |task|
      next if task.success?  # 已发布的不动

      attrs = {}
      if task.platform == 'youtube'
        attrs[:title]       = r[:new_desc]  if r[:new_desc].present?
        attrs[:description] = r[:new_title] if r[:new_title].present?
      else
        attrs[:title] = r[:new_title] if r[:new_title].present?
      end

      next if attrs.empty?
      task.update!(attrs)
      updated += 1
    rescue => e
      errors += 1
      puts "  ⚠️ task##{task.id} 更新失败: #{e.message}"
    end
  end

  puts "✅ 更新完成：成功 #{updated} 条" + (errors > 0 ? "，失败 #{errors} 条" : "")
elsif unmatched_rows.any?
  puts "⚠️ 有 #{unmatched_rows.size} 行未命中。请先核对 video_id/partner_id 与 move_video_ids 的对应关系，确认无误后再执行 confirm。"
end
