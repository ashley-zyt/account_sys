# frozen_string_literal: true

require 'json'
require 'fileutils'

# 发布状况日报：每天晚上 20:00 推送前一日（昨天）发文数据概况到钉钉「发布状况」机器人，
# 同时把昨天的统计结果落一份 JSON 快照，便于后续对比与追溯。
#
# 为什么报告昨天而不是今天：发文数据有采集滞后，当天发文要到次日才抓取完整，
# 所以报告日取「昨天」（数据已完整），对比「前天」。
#
# 数据口径：
#   - 正常状态账号数：统计时 status=正常 的账号总数（每平台），与
#     Account.where(status: 0, platform: X).count 一致。该值只有当前快照、
#     无历史，因此跨天对比依赖每日快照文件（前天取快照值）
#   - 正常发文数：正常状态账号当天（post_stats.post_date = 当日）的发文条数
#   - 对比：报告日（昨天） vs 基准日（前天）
#
# 说明：
#   - 若前天没有快照记录（如首次运行/任务漏跑），则用昨天的数值作为对比基准
#     先记录着（各平台显示「与昨日持平」），明天起即可按实际数据计算
#
# 快照文件：storage/publish_status_snapshots/YYYY-MM-DD.json
#   - normal_accounts = 当日正常状态账号总数（当前快照值），posts = 当日正常账号发文条数
#   - 首写为准（文件已存在则不覆盖），保证「昨天报告里看到的数字」与
#     「今天报告里作为对比基准的数字」一致，历史数字不会因补采数据而漂移
#   - 对比时优先读基准日快照；快照缺失则回退用今天的数值作为基准
#
# 相关命令：
#   手动推送：bundle exec rails runner "PublishStatusReport.run"
#   查看历史：bundle exec rails runner scripts/publish_status_snapshots.rb
#   对比两天：bundle exec rails runner scripts/publish_status_snapshots.rb diff 2026-09-12 2026-09-13
#
# 调度：config/schedule.rb → every :day, at: '20:00' → PublishStatusReport.run
class PublishStatusReport
  # 【临时测试】先发到 agic_zyt（zyt接收）验证功能，测试通过后改回 :publish_status
  NOTIFY_ROBOT = :agic_zyt

  # 展示顺序与名称（key 为 accounts.platform 枚举值）
  PLATFORMS = [
    ['youtube',   'YouTube'],
    ['instagram', 'Instagram'],
    ['twitter',   'X'],
    ['tiktok',    'TikTok'],
    ['facebook',  'Facebook']
  ].freeze

  class << self
    # 生成并推送日报（同时落快照）
    def run
      # 发文数据存在采集滞后：当天发文要到次日才抓取完整，
      # 所以报告日取「昨天」（数据已完整），对比「前天」。
      report_date = Date.yesterday
      base_date   = report_date - 1

      rows = PLATFORMS.map do |platform, label|
        { platform: platform, label: label, stats: stats_for(platform, report_date) }
      end

      # 先落快照再发消息：即使推送失败，统计数据也已经存下来
      path = save_snapshot!(report_date, rows)

      lines = ["#{report_date.strftime('%Y年%m月%d日')}："]
      PLATFORMS.each do |platform, label|
        cur  = rows.find { |r| r[:platform] == platform }[:stats]
        prev = prev_stats_for(platform, base_date, cur)
        lines << build_line(label, cur, prev)
      end

      content = lines.join("\n\n")
      ok = Dingtalk.send_markdown(NOTIFY_ROBOT, '发布状况', content)
      Rails.logger.info "[PublishStatusReport] 快照=#{path || '已存在，未覆盖'}；" \
                        "推送#{ok ? '成功' : '失败'}（报告日=#{report_date} 基准日=#{base_date}，基准来源=#{prev_source(base_date, rows)}）"
      ok
    rescue => e
      Rails.logger.error "[PublishStatusReport] 执行异常: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      false
    end

    # 指定平台、指定日期的发文统计（实时查询）
    # @return [Hash] { accounts: 正常状态账号总数（当前快照）, posts: 该日正常账号发文条数 }
    def stats_for(platform, date)
      {
        accounts: Account.where(status: Account.statuses['正常'],
                                platform: Account.platforms[platform]).count,
        posts:    PostStat.joins(:account)
                          .where(accounts: { status: Account.statuses['正常'],
                                             platform: Account.platforms[platform] })
                          .where(post_date: date)
                          .count
      }
    end

    # ---- 快照读写 ----

    def snapshot_dir
      @snapshot_dir ||= Rails.root.join('storage', 'publish_status_snapshots')
    end

    # 供测试/脚本切换存储目录
    attr_writer :snapshot_dir

    def snapshot_path(date)
      snapshot_dir.join("#{date.strftime('%Y-%m-%d')}.json")
    end

    # 读取指定日期快照；不存在或解析失败返回 nil
    # @return [Hash, nil]
    def load_snapshot(date)
      path = snapshot_path(date)
      return nil unless File.exist?(path)

      data = JSON.parse(File.read(path))
      data.is_a?(Hash) ? data : nil
    rescue => e
      Rails.logger.error "[PublishStatusReport] 读取快照失败 #{path}: #{e.message}"
      nil
    end

    # 写入指定日期快照（首写为准，已存在则不覆盖）
    # @param rows [Array<Hash>] [{ platform:, label:, stats: { accounts:, posts: } }, ...]
    # @return [Pathname, nil] 写入的路径；已存在时返回 nil
    def save_snapshot!(date, rows)
      path = snapshot_path(date)
      if File.exist?(path)
        Rails.logger.info "[PublishStatusReport] 快照已存在，跳过写入: #{path}"
        return nil
      end

      platforms = rows.each_with_object({}) do |row, h|
        h[row[:platform]] = {
          'label'           => row[:label],
          'normal_accounts' => row[:stats][:accounts].to_i,
          'posts'           => row[:stats][:posts].to_i
        }
      end

      payload = {
        'stat_date'    => date.strftime('%Y-%m-%d'),
        'generated_at' => Time.current.strftime('%Y-%m-%dT%H:%M:%S%z'),
        'platforms'    => platforms,
        'totals'       => {
          'normal_accounts' => platforms.values.sum { |v| v['normal_accounts'] },
          'posts'           => platforms.values.sum { |v| v['posts'] }
        }
      }

      FileUtils.mkdir_p(snapshot_dir)
      File.write(path, JSON.pretty_generate(payload))
      path
    end

    # 基准日统计：优先取前天快照；快照缺失（首次运行/漏跑）时，
    # 按需求用昨天的数值作为基准先记录着（各平台显示「与昨日持平」），
    # 明天起即可按实际数据计算
    def prev_stats_for(platform, date, fallback)
      snap = load_snapshot(date)
      from_snapshot = snapshot_stats(snap, platform)
      return from_snapshot if from_snapshot

      fallback
    end

    # 默认取快照目录下的所有快照（按日期升序）
    # @return [Array<Hash>] 已解析的快照数组
    def all_snapshots
      return [] unless Dir.exist?(snapshot_dir)

      Dir[snapshot_dir.join('*.json')].sort.filter_map do |file|
        JSON.parse(File.read(file))
      rescue => e
        Rails.logger.error "[PublishStatusReport] 快照解析失败 #{file}: #{e.message}"
        nil
      end
    end

    # ---- 展示 ----

    # 组装单个平台的播报行
    # 示例：正常状态YouTube账号数 12 个，比昨日**多**1个；正常发文数 30 条，比昨日**少**2条
    def build_line(label, cur, prev)
      account_diff = diff_text(cur[:accounts], prev[:accounts], '个')
      post_diff    = diff_text(cur[:posts],    prev[:posts],    '条')
      "正常状态#{label}账号数 #{cur[:accounts]} 个，#{account_diff}；" \
        "正常发文数 #{cur[:posts]} 条，#{post_diff}"
    end

    # 对比文案：多/少加粗；差异为 0 时显示「与昨日持平」
    def diff_text(cur, prev, unit)
      delta = cur - prev
      return '与昨日持平' if delta.zero?

      word = delta.positive? ? '**多**' : '**少**'
      "比昨日#{word}#{delta.abs}#{unit}"
    end

    # 快照列表表格（列：日期 + 各平台「账号数/发文数」+ 合计）
    def snapshot_table(snapshots)
      header = ['日期'] + PLATFORMS.map { |_p, label| label } + ['合计']
      rows = snapshots.map do |snap|
        platforms = snap['platforms'] || {}
        cells = PLATFORMS.map do |platform, _label|
          s = platforms[platform] || {}
          "#{s['normal_accounts'].to_i}/#{s['posts'].to_i}"
        end
        totals = snap['totals'] || {}
        [snap['stat_date'].to_s] + cells + ["#{totals['normal_accounts'].to_i}/#{totals['posts'].to_i}"]
      end
      render_table([header] + rows)
    end

    # 两天快照对比表格（后一天显示与前一天的变化）
    def snapshot_diff_table(snap_a, snap_b)
      header = ['日期'] + PLATFORMS.map { |_p, label| label }
      rows = [snap_a, snap_b].map do |snap|
        platforms = snap['platforms'] || {}
        cells = PLATFORMS.map do |platform, _label|
          s = platforms[platform] || {}
          "#{s['normal_accounts'].to_i}/#{s['posts'].to_i}"
        end
        [snap['stat_date'].to_s] + cells
      end

      # 变化行
      delta_cells = PLATFORMS.map do |platform, _label|
        a = (snap_a['platforms'] || {})[platform] || {}
        b = (snap_b['platforms'] || {})[platform] || {}
        d_accounts = b['normal_accounts'].to_i - a['normal_accounts'].to_i
        d_posts    = b['posts'].to_i - a['posts'].to_i
        "#{signed(d_accounts)}/#{signed(d_posts)}"
      end
      rows << ['变化'] + delta_cells

      render_table([header] + rows)
    end

    private

    # 从快照中取某平台统计；快照存在但没有该平台时返回 nil（走实时查询兜底）
    def snapshot_stats(snap, platform)
      return nil unless snap

      s = (snap['platforms'] || {})[platform]
      return nil unless s

      { accounts: s['normal_accounts'].to_i, posts: s['posts'].to_i }
    end

    # 基准日数字来源说明（日志用）
    def prev_source(date, rows)
      load_snapshot(date) ? '前天快照' : '昨日数值（前天无快照，先记录着）'
    end

    def signed(number)
      number.positive? ? "+#{number}" : number.to_s
    end

    # 等宽表格渲染（按列宽左对齐）
    def render_table(rows)
      widths = rows.transpose.map { |col| col.map { |c| display_width(c) }.max }
      rows.map do |row|
        row.each_with_index.map { |cell, i| pad(cell, widths[i]) }.join('  ').rstrip
      end.join("\n")
    end

    # 中文按 2 个字符宽度计算，保证列对齐
    def display_width(str)
      str.to_s.each_char.sum { |c| c.bytesize > 1 ? 2 : 1 }
    end

    def pad(str, width)
      str.to_s + (' ' * [width - display_width(str), 0].max)
    end
  end
end
