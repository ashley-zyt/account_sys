# 临时脚本：补查「twitter 已发私信但对方未回复」的 KOL，并结算。
#
# 范围：KOL 状态 ∉ [待回复, 洽谈中]，且其 twitter 联系方式有「发送成功」但无 incoming 回复。
# 处理（分两步，机器端查回复是异步任务，回调需要时间）：
#   第一步 EXEC=1：
#     - 发起账号正常 → 触发机器端查回复（浏览器通道），记录清单；
#       * 有回复 → 机器回调自动 apply_reply_result 入库并转「待回复」，无需本脚本处理
#     - 发起账号失效（停用/封禁等）→ KOL 直接改「无法联系」
#   第二步 SETTLE=1（等机器端任务跑完后执行）：
#     - 清单里仍无 incoming 回复的联系方式 → 置「未回复」，KOL 也置「未回复」（以后不再触发）
#
# 用法：
#   预览：   bundle exec rails runner scripts/settle_twitter_unreplied_kols.rb
#   触发：   EXEC=1 bundle exec rails runner scripts/settle_twitter_unreplied_kols.rb
#   结算：   SETTLE=1 bundle exec rails runner scripts/settle_twitter_unreplied_kols.rb
#   分批：   可加 IDS=1,2,3 只看指定 KOL

PHASE_EXEC   = ENV['EXEC'] == '1'
PHASE_SETTLE = ENV['SETTLE'] == '1'
IDS_FILE     = Rails.root.join('tmp', 'twitter_unreplied_checked_ids.txt')

# 排除的 KOL 状态：待回复、洽谈中
EXCLUDED_STATUSES = [Kol.statuses[:replied_unprocessed], Kol.statuses[:negotiating]].freeze

raw_ids = ENV['IDS'].to_s
BATCH_IDS = raw_ids.split(/[,\s]+/).map(&:to_i).reject(&:zero?).uniq

def account_usable?(account)
  account.present? && account.status == '正常'
end

# 收集符合条件的「twitter 联系方式」（发了 sent_success、无 incoming 回复）
def collect_target_contacts(kol_ids)
  contacts = []
  KolContact.where(kol_id: kol_ids, platform: KolContact.platforms[:twitter])
            .includes(:kol).find_each do |c|
    has_sent = c.kol_messages.exists?(direction: KolMessage.directions[:outgoing],
                                      status: KolMessage.statuses[:sent_success])
    has_in = c.kol_messages.exists?(direction: KolMessage.directions[:incoming])
    contacts << c if has_sent && !has_in
  end
  contacts
end

# ================= 第二步：结算 =================
if PHASE_SETTLE
  unless File.exist?(IDS_FILE)
    puts "未找到检查清单 #{IDS_FILE}，请先执行第一步（EXEC=1）"
    exit 1
  end

  contact_ids = File.read(IDS_FILE).split.map(&:to_i).uniq
  if BATCH_IDS.any?
    scoped = KolContact.where(id: contact_ids, kol_id: BATCH_IDS).pluck(:id)
    puts "指定 KOL #{BATCH_IDS.join(',')}：结算 #{scoped.size} 个联系方式（清单共 #{contact_ids.size} 个，保留不动）"
    contact_ids = scoped
  else
    File.delete(IDS_FILE)
  end
  puts "结算联系方式 #{contact_ids.size} 个"
  puts '-' * 60

  unresponsive = already_replied = errors = 0
  KolContact.where(id: contact_ids).includes(:kol).find_each do |contact|
    kol = contact.kol
    has_in = contact.kol_messages.exists?(direction: KolMessage.directions[:incoming])
    if has_in
      # 回调已入库并转「待回复」，跳过
      already_replied += 1
      puts "[已回复] KOL##{kol.id} #{kol.name}（contact##{contact.id}）已由回调转待回复"
    else
      contact.update!(status: :unresponsive, monitor_until: nil, next_poll_at: nil)
      if kol.status.to_s == 'contacting' || kol.status.to_s == 'pending'
        kol.update!(status: :unresponsive, next_action_at: nil)
      end
      unresponsive += 1
      puts "[未回复] KOL##{kol.id} #{kol.name}（contact##{contact.id}）置未回复"
    end
  rescue => e
    errors += 1
    Rails.logger.error "[SettleTwitterUnreplied] contact##{contact&.id} 结算异常: #{e.message}"
  end

  puts '=' * 60
  puts "结算完成：置未回复 #{unresponsive}，已回复跳过 #{already_replied}，异常 #{errors}"
  exit
end

# ================= 第一步：预览 / 触发查回复 + 失效改无法联系 =================
kols = Kol.where.not(status: EXCLUDED_STATUSES)
kols = kols.where(id: BATCH_IDS) if BATCH_IDS.any?
kol_ids = kols.pluck(:id)

targets = collect_target_contacts(kol_ids)
puts "目标 twitter 联系方式（发了没回复）：#{targets.size} 个"

# 按发起账号是否可用分组
checkable = []      # [[contact, account], ...] 账号正常，可查回复
invalid_account = [] # [[contact, account], ...] 账号失效，改无法联系
no_account = []      # 无发起账号记录

targets.each do |contact|
  account = contact.last_outgoing_account
  if account.nil?
    no_account << contact
  elsif account_usable?(account)
    checkable << [contact, account]
  else
    invalid_account << [contact, account]
  end
end

puts '-' * 60
puts "发起账号正常（可查回复）：#{checkable.size}"
puts "发起账号失效（改无法联系）：#{invalid_account.size}"
puts "无发起账号（跳过）：#{no_account.size}"

# 失效账号对应的 KOL（去重，预览时列出）
invalid_kol_ids = invalid_account.map { |c, _a| c.kol_id }.uniq
puts "\n失效账号涉及的 KOL id：#{invalid_kol_ids.join(', ')}" if invalid_kol_ids.any?

exit unless PHASE_EXEC

FileUtils.mkdir_p(File.dirname(IDS_FILE))
triggered = failed = 0

# 1) 失效账号 → KOL 改「无法联系」
invalid_kol_ids.each do |kid|
  k = Kol.find_by(id: kid)
  next if k.nil? || k.status.to_s == 'unreachable'
  k.update!(status: :unreachable, next_action_at: nil)
  puts "[改无法联系] KOL##{k.id} #{k.name}"
end

# 2) 正常账号 → 触发查回复
checkable.each do |contact, account|
  result = KolOutreachApi.check_reply(platform: contact.platform, account: account, contact: contact)
  if result[:async]
    File.open(IDS_FILE, 'a') { |f| f.puts contact.id }
    triggered += 1
    puts "[已触发] contact##{contact.id}（KOL##{contact.kol_id}）用账号##{account.id}"
  else
    failed += 1
    puts "[失败] contact##{contact.id}：#{result[:error].presence || '机器端未受理'}"
  end
rescue => e
  failed += 1
  Rails.logger.error "[SettleTwitterUnreplied] contact##{contact&.id} 触发异常: #{e.message}"
end

puts '=' * 60
puts "第一步完成：改无法联系 #{invalid_kol_ids.size} 个 KOL，触发查回复 #{triggered}，触发失败 #{failed}"
puts "等机器端任务完成后，执行第二步：SETTLE=1 bundle exec rails runner scripts/settle_twitter_unreplied_kols.rb"
