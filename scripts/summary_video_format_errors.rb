# -*- coding: utf-8 -*-
# 汇总「视频格式不适配」类发布错误：按「工作模式 × 主题」统计命中数量，
# 并列出命中的去重错误样本，用于判断视频出处和失败原因。
#
# 用法（只读统计，不改动任何数据）：
#   bundle exec rails runner scripts/summary_video_format_errors.rb
#
# 可选参数：
#   数字           只统计最近 N 天内的任务（按 updated_at / created_at 判定），默认全部
#   list           额外打印「命中错误信息的去重样本（按出现次数排序）」
#   list=20        调整样本条数（默认 30）
#
# 示例：
#   bundle exec rails runner scripts/summary_video_format_errors.rb 30 list=50
#
# 关键词匹配不区分大小写。若实际错误文本与下方关键词不符，直接改 FORMAT_KEYWORDS 再跑。

# 视频格式不适配相关的错误关键词（中英文常见表述）
FORMAT_KEYWORDS = [
  '视频格式',
  '格式不支持',
  '格式不适配',
  '格式不正确',
  '格式错误',
  '无法解析',
  '解码失败',
  '无法播放',
  '无法处理视频',
  'video format',
  'format not supported',
  'unsupported format',
  'format unsupported',
  'not a valid video',
  'invalid video',
  'video not supported',
  'unsupported video',
  'codec',
  'invalid media type',
  'media type not'
].freeze

# 解析参数
args = ARGV.dup
days = args.find { |a| a =~ /\A\d+\z/ }&.to_i          # 数字 = 最近 N 天
list_arg = args.find { |a| a.start_with?('list') }       # list 或 list=N
show_samples = !list_arg.nil?
sample_limit = list_arg.to_s =~ /list=(\d+)/ ? $1.to_i : 30

def match_format_error?(msg)
  return false if msg.blank?
  m = msg.to_s.downcase
  FORMAT_KEYWORDS.any? { |kw| m.include?(kw.downcase) }
end

# 汇总结构：{ [mode_name, theme] => count }
summary = Hash.new(0)
# 错误样本：{ error_msg 截断 => count }
samples = Hash.new(0)
# 工作模式维度小计
mode_subtotal = Hash.new(0)
# 主题维度小计（跨模式）
theme_subtotal = Hash.new(0)

WorkMode.resource_modes.each do |mode|
  model = mode.task_model_class
  next unless model.column_names.include?('theme') && model.column_names.include?('error_msg')

  scope = model.where("error_msg IS NOT NULL AND error_msg != ''")
  scope = scope.where('created_at >= ?', days.days.ago) if days && days > 0

  scope.pluck(:theme, :error_msg).each do |theme, msg|
    next unless match_format_error?(msg)

    theme_label = theme.presence || '(无主题)'
    summary[[mode.name, theme_label]] += 1
    mode_subtotal[mode.name] += 1
    theme_subtotal[theme_label] += 1

    if show_samples
      key = msg.to_s.strip[0, 200]
      samples[key] += 1
    end
  end
end

puts "=" * 78
puts "视频格式不适配错误汇总（#{days && days > 0 ? "最近 #{days} 天" : '全部历史'}）"
puts "匹配关键词：#{FORMAT_KEYWORDS.join(' / ')}"
puts "=" * 78

if summary.empty?
  puts "未命中任何格式不适配错误。"
  puts "提示：可先加 list 参数查看实际错误样本，或核对 FORMAT_KEYWORDS 关键词是否准确。"
  exit
end

# 1. 按「工作模式 × 主题」明细
puts
puts "一、按「工作模式 × 主题」明细"
puts "-" * 78
puts format("  %-12s %-40s %s", "工作模式", "主题", "数量")
puts "-" * 78
summary.sort_by { |(mode, theme), count| [-count, mode, theme] }.each do |(mode, theme), count|
  puts format("  %-12s %-40s %d", mode, theme, count)
end

# 2. 按工作模式小计
puts
puts "二、按工作模式汇总"
puts "-" * 78
mode_subtotal.sort_by { |_m, c| -c }.each do |mode, count|
  puts format("  %-12s %d", mode, count)
end
puts format("  %-12s %d", "合计", mode_subtotal.values.sum)

# 3. 按主题小计（跨工作模式，直接对应视频出处）
puts
puts "三、按主题汇总（跨工作模式，用于判断视频出处）"
puts "-" * 78
theme_subtotal.sort_by { |_t, c| -c }.each do |theme, count|
  puts format("  %-40s %d", theme, count)
end

# 4. 错误样本
if show_samples
  puts
  puts "四、命中错误信息的去重样本（前 #{sample_limit} 条，按出现次数排序）"
  puts "-" * 78
  samples.sort_by { |_msg, c| -c }.first(sample_limit).each_with_index do |(msg, count), i|
    puts format("  [%2d] (%d 次) %s", i + 1, count, msg)
  end
end

puts
puts "完成。"
