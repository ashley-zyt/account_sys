# 临时脚本：处理「无法联系」状态的 KOL —— 补查一次回复
#
# 背景：321 个 KOL 处于 unreachable（无法联系），需要按「当时发起私信的内部账号」分流：
#   - 账号仍「正常」→ 把联系方式/KOL 恢复为联系中，并触发一次机器端查回复（浏览器模拟）：
#       有回复 → 机器回调自动入库、KOL 转「待回复」（走现有 apply_reply_result 链路）
#       没回复 → 第二步结算时置为「未回复」
#   - 账号已封禁/停用/未登录等 → 保持「无法联系」不动
#
# 分两步执行（机器端查回复是异步任务，回调需要时间）：
#   第一步（预览）：  bundle exec rails runner scripts/settle_unreachable_kols.rb
#   第一步（执行）：  EXEC=1  bundle exec rails runner scripts/settle_unreachable_kols.rb
#                     触发查回复任务，并把本次检查的联系方式 id 写入 tmp/kol_unreachable_checked_ids.txt
#   第二步（结算）：  SETTLE=1 bundle exec rails runner scripts/settle_unreachable_kols.rb
#                     等机器端任务跑完后执行：有回复的保持「待回复」，没回复的置「未回复」

PHASE_EXEC   = ENV['EXEC'] == '1'
PHASE_SETTLE = ENV['SETTLE'] == '1'
IDS_FILE     = Rails.root.join('tmp', 'kol_unreachable_checked_ids.txt')

# 可选：指定 KOL id 分批处理，逗号或空格分隔，如 IDS=1,2,3 或 IDS="1 2 3"
# 也可以用 IDS_FILE 指定清单文件（每行一个 KOL id，如 rework_unreachable_kols.rb 输出的清单）
raw_ids = ENV['IDS'].to_s
if raw_ids.empty? && ENV['IDS_FILE'].present? && File.exist?(ENV['IDS_FILE'])
  raw_ids = File.read(ENV['IDS_FILE'])
end
BATCH_IDS = raw_ids.split(/[,\s]+/).map(&:to_i).reject(&:zero?).uniq

# 账号「正常」才允许查回复（其余状态视为不可用，保持无法联系）
def account_usable?(account)
  account.present? && account.status == '正常'
end

if PHASE_SETTLE
  # ================= 第二步：结算 =================
  unless File.exist?(IDS_FILE)
    puts "未找到检查清单 #{IDS_FILE}，请先执行第一步（EXEC=1）"
    exit 1
  end

  contact_ids = File.read(IDS_FILE).split.map(&:to_i).uniq
  if BATCH_IDS.any?
    # 只结算指定 KOL 的联系方式，其余 id 留在清单里给后续批次
    scoped = KolContact.where(id: contact_ids, kol_id: BATCH_IDS).pluck(:id)
    remaining = contact_ids - scoped
    File.write(IDS_FILE, remaining.join("\n"))
    puts "指定 KOL #{BATCH_IDS.join(',')}：结算 #{scoped.size} 个联系方式（清单中其余 #{remaining.size} 个留给后续批次）"
    contact_ids = scoped
  else
    # 不带 IDS = 一次性结算全部，结算完删清单
    File.delete(IDS_FILE)
  end
  puts "结算联系方式 #{contact_ids.size} 个"

  replied = no_reply = errors = 0
  KolContact.where(id: contact_ids).find_each do |contact|
    kol = contact.kol
    if kol.kol_messages.exists?(kol_contact_id: contact.id, direction: :incoming)
      replied += 1
      puts "[已回复] KOL##{kol.id} #{kol.name} → 保持「待回复」"
    else
      contact.update!(status: :unresponsive, monitor_until: nil, next_poll_at: nil)
      # KOL 仍处于联系中才置未回复，避免覆盖回调已流转的状态
      if kol.reload.contacting?
        kol.update!(status: :unresponsive, next_action_at: nil)
        no_reply += 1
        puts "[未回复] KOL##{kol.id} #{kol.name}"
      else
        puts "[跳过] KOL##{kol.id} #{kol.name} 当前状态=#{kol.status}（回调已处理）"
      end
    end
  rescue => e
    errors += 1
    Rails.logger.error "[SettleUnreachable] contact##{contact&.id} 异常: #{e.message}"
  end

  puts '=' * 60
  puts "结算完成：已回复(保持待回复) #{replied}，置未回复 #{no_reply}，异常 #{errors}"
  exit
end

# ================= 第一步：预览 / 触发查回复 =================
kols = Kol.unreachable
kols = kols.where(id: BATCH_IDS) if BATCH_IDS.any?
kols = kols.to_a
suffix = BATCH_IDS.any? ? "（指定 id：#{BATCH_IDS.join(',')}）" : ''
puts "无法联系 KOL：#{kols.size} 个#{suffix}"

checkable = []   # [[contact, account], ...]
stats = { no_history: 0, account_bad: 0, already_replied: 0 }

kols.each do |kol|
  # 有「发送成功」私信记录的联系方式
  contact_ids = KolMessage.where(kol_id: kol.id, direction: :outgoing, status: :sent_success)
                          .distinct.pluck(:kol_contact_id)
  if contact_ids.empty?
    stats[:no_history] += 1
    next
  end

  kol_checkable = []
  contact_ids.each do |cid|
    contact = KolContact.find_by(id: cid)
    next if contact.nil? || contact.replied? # 已回复的不动
    account = contact.last_outgoing_account
    if account_usable?(account)
      kol_checkable << [contact, account]
    else
      stats[:account_bad] += 1
    end
  end
  checkable.concat(kol_checkable)
end

puts '-' * 60
puts "无私信历史（保持无法联系）：#{stats[:no_history]}"
puts "发起账号不可用（保持无法联系）：#{stats[:account_bad]} 处"
puts "可补查回复：#{checkable.size} 个联系方式"
puts '--- 预览模式（EXEC=1 触发查回复 / SETTLE=1 结算）---' unless PHASE_EXEC

exit unless PHASE_EXEC

FileUtils.mkdir_p(File.dirname(IDS_FILE))
triggered = failed = 0

checkable.each do |contact, account|
  kol = contact.kol
  # 恢复联系中，让回调链路能正常流转（有回复 → replied / 待回复）
  contact.update!(status: :contacting, monitor_until: 14.days.from_now, next_poll_at: nil)
  kol.update!(status: :contacting, next_action_at: nil) unless kol.replied_unprocessed? || kol.in_conversation?

  result = KolOutreachApi.check_reply(platform: contact.platform, account: account, contact: contact)
  if result[:async]
    File.open(IDS_FILE, 'a') { |f| f.puts contact.id }
    triggered += 1
    puts "[已触发] KOL##{kol.id} #{kol.name} contact##{contact.id}（#{contact.platform}）账号##{account.id}"
  else
    failed += 1
    # 触发失败（机器不通等）：回退状态，等待人工处理
    contact.update!(status: :unresponsive, monitor_until: nil, next_poll_at: nil)
    kol.update!(status: :unreachable, next_action_at: nil) unless kol.replied_unprocessed? || kol.in_conversation?
    puts "[失败] KOL##{kol.id} contact##{contact.id}：#{result[:error].presence || '机器端未受理'}"
  end
rescue => e
  failed += 1
  Rails.logger.error "[SettleUnreachable] contact##{contact&.id} 触发异常: #{e.message}"
end

puts '=' * 60
puts "第一步完成：触发查回复 #{triggered}，触发失败 #{failed}"
puts "等机器端任务完成后，执行第二步：SETTLE=1 bundle exec rails runner scripts/settle_unreachable_kols.rb"
