# 临时脚本：把所有 Instagram 联系方式改为「不可私信」（messaging_enabled=false）。
#
# 用法（先预览，再执行）：
#   预览： bundle exec rails runner scripts/disable_instagram_contacts.rb
#   执行： EXEC=1 bundle exec rails runner scripts/disable_instagram_contacts.rb

PHASE_EXEC = ENV['EXEC'] == '1'

scope = KolContact.where(platform: KolContact.platforms[:instagram])

puts "Instagram 联系方式总数: #{scope.count}"
puts "  其中当前可私信（messaging_enabled=true）: #{scope.where(messaging_enabled: true).count}"
puts "  其中当前已不可私信: #{scope.where(messaging_enabled: false).count}"

exit unless PHASE_EXEC

n = scope.where(messaging_enabled: true).update_all(messaging_enabled: false, updated_at: Time.current)
puts "已把 #{n} 个 Instagram 联系方式改为不可私信"
