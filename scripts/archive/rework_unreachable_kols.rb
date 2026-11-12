# 一次性脚本：批量处理「无法联系」(unreachable) 的 KOL
#
# 背景：这批 KOL 成因混杂——
#   1) 早期 X 走 API 发送，API 被禁后误判为无法联系
#   2) 发起私信的账号失效，无法查回复
#   3) 发送失败后没有轮换到其他联系方式（历史 bug，已修复）
#
# 处理分流（EXEC=1 执行，否则仅预览）：
#   A 类·直接复活：存在可自动触达的联系方式（X/Instagram、未联系、开私信、账号池支持）
#       → KOL 回「待联系」，下一轮自动调度重新触达；
#         名下卡在「联系中」且未回复的 X/IG 联系方式一并退回「未联系」
#   B 类·补查回复：无可用渠道，但有发送成功记录且发起账号仍「正常」
#       → kol id 写入 tmp/unreachable_rework_check_ids.txt，
#         用 settle_unreachable_kols.rb 分批补查（有回复→待回复 / 没回复→未回复）
#   C 类·账号失效：有发送记录但发起账号已封禁/停用，且无可用渠道 → 保持无法联系（人工处理）
#   D 类·从未发出：无任何发送成功记录，也无可用渠道 → 保持无法联系
#
# 用法：
#   预览： bundle exec rails runner scripts/rework_unreachable_kols.rb
#   执行： EXEC=1 bundle exec rails runner scripts/rework_unreachable_kols.rb
#   B 类后续（分批，等机器端查回复跑完后再结算）：
#     IDS_FILE=tmp/unreachable_rework_check_ids.txt EXEC=1 bundle exec rails runner scripts/settle_unreachable_kols.rb
#     IDS_FILE=tmp/unreachable_rework_check_ids.txt SETTLE=1 bundle exec rails runner scripts/settle_unreachable_kols.rb

PHASE_EXEC = ENV['EXEC'] == '1'
OUT_FILE   = Rails.root.join('tmp', 'unreachable_rework_check_ids.txt')

# 可选：指定 KOL id 分批处理，逗号或空格分隔
BATCH_IDS = ENV['IDS'].to_s.split(/[,\s]+/).map(&:to_i).reject(&:zero?).uniq

# 账号「正常」才可补查回复（与 settle_unreachable_kols.rb 口径一致）
def account_usable?(account)
  account.present? && account.status == '正常'
end

# A 类候选：X/IG 渠道且开启私信，「未联系」可直接用；
# 「联系中」但未回复的属于历史发送失败卡死（当时失败后没有退回），一并纳入复活
def revivable_contacts(kol)
  kol.kol_contacts
     .where(platform: KolContact::ENABLED_PLATFORMS, messaging_enabled: true)
     .where(status: KolContact.statuses.slice(:active, :contacting).values)
     .reject(&:replied?)
     .select { |c| KolAccountAllocator.supported_platform?(c.platform) }
end

scope = Kol.where(status: :unreachable)
scope = scope.where(id: BATCH_IDS) if BATCH_IDS.any?

puts "无法联系 KOL 总数：#{scope.count}（#{PHASE_EXEC ? '执行模式' : '预览模式'}）"
puts '-' * 60

stats = { revived: 0, to_check: 0, account_bad: 0, no_history_disabled: 0, no_history_no_channel: 0 }
check_ids = []
revived_samples = []

scope.order(:id).find_each do |kol|
  # ---- A 类：有可复活渠道（未联系 / 卡死未回复的 X/IG 联系方式）→ 复活 ----
  revivable = revivable_contacts(kol)
  if revivable.any?
    if PHASE_EXEC
      # 卡在「联系中」的退回「未联系」，与其他联系方式一起参与下一轮轮换
      revivable.select(&:contacting?)
               .each { |c| c.update!(status: :active, monitor_until: nil, next_poll_at: nil) }
      kol.update!(status: :pending, next_action_at: nil)
    end
    stats[:revived] += 1
    revived_samples << kol.id if revived_samples.size < 20
    next
  end

  # ---- 无可用渠道：看是否有发送成功历史 ----
  contact_ids = KolMessage.where(kol_id: kol.id, direction: :outgoing, status: :sent_success)
                          .distinct.pluck(:kol_contact_id)

  if contact_ids.empty?
    # ---- D 类：从未发出过私信 ----
    # 细分：渠道全被停用（历史明确失败，如 DM 关闭）vs 完全没有 X/IG 渠道
    if kol.kol_contacts.where(platform: KolContact::ENABLED_PLATFORMS, messaging_enabled: true).exists?
      stats[:no_history_disabled] += 1
    else
      stats[:no_history_no_channel] += 1
    end
    next
  end

  # ---- B / C 类：有发送历史，看发起账号是否可用 ----
  checkable = contact_ids.any? do |cid|
    c = KolContact.find_by(id: cid)
    c.present? && !c.replied? && account_usable?(c.last_outgoing_account)
  end

  if checkable
    check_ids << kol.id
    stats[:to_check] += 1
  else
    stats[:account_bad] += 1
  end
end

puts "A 类·可复活（回待联系自动重发）：#{stats[:revived]}"
puts "B 类·可补查回复（写入清单）：    #{stats[:to_check]}"
puts "C 类·发起账号失效（保持原状）：  #{stats[:account_bad]}"
puts "D 类·从未发出私信（保持原状）：  #{stats[:no_history_disabled] + stats[:no_history_no_channel]}"
puts "  其中渠道全停用（历史失败）：    #{stats[:no_history_disabled]}"
puts "  其中没有 X/IG 渠道：           #{stats[:no_history_no_channel]}"

puts 'A 类示例：' + revived_samples.join(',') unless revived_samples.empty?

exit unless PHASE_EXEC

# B 类清单写入文件，供 settle_unreachable_kols.rb 的 IDS_FILE 使用
FileUtils.mkdir_p(File.dirname(OUT_FILE))
File.write(OUT_FILE, check_ids.uniq.join("\n")) if check_ids.any?
puts "B 类 KOL id 已写入 #{OUT_FILE}（#{check_ids.uniq.size} 个）"
puts '后续执行：'
puts "  IDS_FILE=#{OUT_FILE} EXEC=1 bundle exec rails runner scripts/settle_unreachable_kols.rb"
puts '  （等机器端查回复完成后）'
puts "  IDS_FILE=#{OUT_FILE} SETTLE=1 bundle exec rails runner scripts/settle_unreachable_kols.rb"
