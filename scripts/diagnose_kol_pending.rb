# 临时脚本：诊断 KolScheduler.run 为什么没有发私信（pending KOL 是否有可用 twitter 联系方式）。
# 只读，不改库。
#
# 用法：
#   bundle exec rails runner scripts/diagnose_kol_pending.rb

pending = Kol.where(status: Kol.statuses[:pending], variables_incomplete: false)
due = pending.where("next_action_at IS NULL OR next_action_at <= ?", Time.current)

puts "待联系（pending，变量完整）KOL 总数: #{pending.count}"
puts "  其中到期可处理: #{due.count}"
puts "=" * 60

# 分平台看可私信联系方式
tw_ok = KolContact.where(platform: KolContact.platforms[:twitter], messaging_enabled: true, status: KolContact.statuses[:active])
ig_ok = KolContact.where(platform: KolContact.platforms[:instagram], messaging_enabled: true, status: KolContact.statuses[:active])

puts "全系统可私信联系方式："
puts "  twitter: #{tw_ok.count}"
puts "  instagram: #{ig_ok.count}"

# pending KOL 里有多少有可用的 twitter 联系方式
pending_ids = due.pluck(:id)
puts "=" * 60
puts "到期 pending KOL 中："
puts "  有可用 twitter 联系方式的: #{tw_ok.where(kol_id: pending_ids).distinct.count(:kol_id)}"
puts "  有可用 instagram 联系方式的: #{ig_ok.where(kol_id: pending_ids).distinct.count(:kol_id)}"

# 没有可用联系方式的 pending KOL 会被 run_outreach 标记为 unreachable
no_usable = due.where.not(id: tw_ok.where(kol_id: pending_ids).select(:kol_id))
              .where.not(id: ig_ok.where(kol_id: pending_ids).select(:kol_id))
puts "  两者都没有（会被标为无法联系）: #{no_usable.count}"

# twitter 联系方式状态分布（诊断为什么 twitter 没进候选）
puts "=" * 60
puts "twitter 联系方式状态分布（全系统）："
KolContact.where(platform: KolContact.platforms[:twitter])
          .group(:status, :messaging_enabled).count
          .sort.each do |(status, enabled), n|
  puts "  status=#{status} messaging_enabled=#{enabled}: #{n}"
end

# 934 账号状态
puts "=" * 60
a = Account.find_by(id: 934)
if a
  puts "934 账号：status=#{a.status} X授权=#{a.x_credential&.auth_status} 休眠=#{a.kol_sleeping?}"
else
  puts "934 账号不存在！"
end
