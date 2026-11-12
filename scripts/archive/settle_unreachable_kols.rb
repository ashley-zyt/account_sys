# 临时脚本：检查「无法联系」状态的 KOL 是否有回复 —— 只采集、不流转状态
#
# 背景：unreachable（无法联系）的 KOL，按「当时发起私信的内部账号」可查的触发一次机器端查回复：
#   - 有回复 → 机器回调自动把回复入库（KolMessage incoming），KOL 转「待回复」（走现有 apply_reply_result 链路）
#   - 没回复 → 什么都不动（保持「无法联系」），等看完回复量再决定后续处理
#
# 用法（机器端查回复是异步任务，回调需要时间）：
#   第一步（预览）：  bundle exec rails runner scripts/settle_unreachable_kols.rb
#   第一步（执行）：  EXEC=1  bundle exec rails runner scripts/settle_unreachable_kols.rb
#                     触发查回复任务，并把本次检查的联系方式 id 写入 tmp/kol_unreachable_checked_ids.txt
#   第二步（只统计）：SETTLE=1 bundle exec rails runner scripts/settle_unreachable_kols.rb
#                     只统计清单里有多少已回复/未回复（附回复预览），不改任何状态

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

# 账号「正常」才允许查回复（其余状态视为不可用）
def account_usable?(account)
  account.present? && account.status == '正常'
end

if PHASE_SETTLE
  # ================= 第二步：只统计回复量（不改状态） =================
  unless File.exist?(IDS_FILE)
    puts "未找到检查清单 #{IDS_FILE}，请先执行第一步（EXEC=1）"
    exit 1
  end

  contact_ids = File.read(IDS_FILE).split.map(&:to_i).uniq
  if BATCH_IDS.any?
    # 只统计指定 KOL 的联系方式
    scoped = KolContact.where(id: contact_ids, kol_id: BATCH_IDS).pluck(:id)
    puts "指定 KOL #{BATCH_IDS.join(',')}：统计 #{scoped.size} 个联系方式（清单共 #{contact_ids.size} 个，保留不动）"
    contact_ids = scoped
  end
  puts "统计联系方式 #{contact_ids.size} 个"
  puts '-' * 60

  replied = no_reply = errors = 0
  KolContact.where(id: contact_ids).includes(:kol).find_each do |contact|
    kol = contact.kol
    incoming = KolMessage.where(kol_id: kol.id, kol_contact_id: contact.id, direction: :incoming).order(occurred_at: :desc)
    if incoming.exists?
      replied += 1
      latest = incoming.first
      preview = latest.content.to_s.gsub(/\s+/, ' ').truncate(40)
      puts "[已回复] KOL##{kol.id} #{kol.name}（#{contact.platform}）共 #{incoming.size} 条，最新 #{latest.occurred_at&.strftime('%m-%d %H:%M')}：#{preview}"
    else
      no_reply += 1
      puts "[未回复] KOL##{kol.id} #{kol.name}（#{contact.platform}）状态保持 #{kol.status}"
    end
  rescue => e
    errors += 1
    Rails.logger.error "[SettleUnreachable] contact##{contact&.id} 统计异常: #{e.message}"
  end

  puts '=' * 60
  puts "统计完成：已回复 #{replied}，未回复 #{no_reply}，异常 #{errors}（所有状态均未改动；已回复的 KOL 已由回调自动转为待回复并入库）"
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
  # 只触发查回复，不改 KOL/联系方式状态（有回复由回调自动入库并转待回复，没回复保持无法联系）
  result = KolOutreachApi.check_reply(platform: contact.platform, account: account, contact: contact)
  if result[:async]
    File.open(IDS_FILE, 'a') { |f| f.puts contact.id }
    triggered += 1
    puts "[已触发] KOL##{kol.id} #{kol.name} contact##{contact.id}（#{contact.platform}）账号##{account.id}"
  else
    failed += 1
    puts "[失败] KOL##{kol.id} contact##{contact.id}：#{result[:error].presence || '机器端未受理'}（状态未改动）"
  end
rescue => e
  failed += 1
  Rails.logger.error "[SettleUnreachable] contact##{contact&.id} 触发异常: #{e.message}"
end

puts '=' * 60
puts "第一步完成：触发查回复 #{triggered}，触发失败 #{failed}"
puts "等机器端任务完成后，执行第二步统计：SETTLE=1 bundle exec rails runner scripts/settle_unreachable_kols.rb"
