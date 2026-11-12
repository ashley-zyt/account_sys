# 重新验证「无法联系(unreachable)」的 KOL：
#   恢复它们被停用(disabled)的 twitter 联系方式，重新入队，用正常账号重发私信验证。
#   发成功 = 之前误判（其实能联系）；仍被拒 = 真无法联系（会被现在的代码正确停用）。
#
# 为什么是「恢复被停用的 twitter 联系方式」：unreachable 的成因之一就是
#   「对方拒绝私信」/「@username 无效」被停用了联系方式（其中部分是历史误判，如发送账号有风险）。
#   平台不支持私信（linkedin 等）或私信开关关的，不在此脚本范围。
#
# 用法（在 account_sys 服务器上跑）：
#   预览（只列出，不改数据）：
#     bundle exec rails runner scripts/reverify_unreachable_kols.rb
#   执行（恢复联系方式 + 重新入队）：
#     bundle exec rails runner scripts/reverify_unreachable_kols.rb confirm

confirm = ARGV.include?('confirm')

# 无法联系、且有待验证（被停用 twitter 联系方式）的 KOL
targets = []  # [kol, contact, 停用原因]
Kol.where(status: :unreachable).includes(:kol_contacts).find_each do |kol|
  kol.kol_contacts.where(status: :disabled, platform: :twitter).each do |contact|
    last_failed = contact.kol_messages.where(direction: :outgoing, status: :sent_failed)
                          .order(id: :desc).first
    targets << [kol, contact, last_failed&.error_msg]
  end
end

puts "=== 无法联系、且有待重新验证的 twitter 联系方式 ==="
puts "共 #{targets.size} 个联系方式"
targets.each do |kol, contact, reason|
  puts "  KOL##{kol.id} #{kol.name}  contact##{contact.id} #{contact.url}"
  puts "      停用原因: #{reason.presence || '(无失败记录)'}"
end

if confirm
  restored = 0
  kol_ids = []
  targets.each do |kol, contact, _|
    next if contact.active?
    contact.update!(status: :active)
    restored += 1
    kol_ids << kol.id
  end

  requeued = 0
  skipped = []
  Kol.where(id: kol_ids.uniq).find_each do |kol|
    if kol.enqueue!  # 内部校验：变量完整 + 有可私信联系方式
      requeued += 1
    else
      skipped << "#{kol.id} #{kol.name}（缺变量或仍无可私信联系方式）"
    end
  end

  puts "\n完成：恢复 #{restored} 个联系方式，重新入队 #{requeued} 个 KOL"
  if skipped.any?
    puts "未入队（需人工检查）："
    skipped.each { |s| puts "  - #{s}" }
  end
  puts "已入队的 KOL 将用正常账号重发私信：发成功=之前误判；仍被拒=真无法联系（自动再次停用）。"
else
  puts "\n以上为预览，未改动任何数据。"
  puts "执行：bundle exec rails runner scripts/reverify_unreachable_kols.rb confirm"
end
