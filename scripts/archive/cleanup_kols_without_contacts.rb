# 清理：删除 id > 757 且没有任何联系方式（kol_contacts）的 KOL
#
# 用法：
#   bundle exec rails runner scripts/cleanup_kols_without_contacts.rb        # 直接删除
#   bundle exec rails runner scripts/cleanup_kols_without_contacts.rb dry    # 只预览，不删除

MIN_ID = 757

def run
  dry_run = ARGV.include?('dry')

  # 没有联系方式的 KOL：id > 757，且 kol_id 不出现在 kol_contacts 里
  scope = Kol.where('id > ?', MIN_ID)
             .where.not(id: KolContact.select(:kol_id))

  puts "id > #{MIN_ID} 且无联系方式的 KOL 共 #{scope.count} 条#{dry_run ? '（预览，不删除）' : ''}"

  if dry_run
    scope.find_each { |k| puts "  [预览] #{k.id} | #{k.name}" }
    return
  end

  deleted = 0
  scope.find_each do |k|
    k.destroy
    deleted += 1
    puts "  删除: #{k.id} | #{k.name}"
  end

  puts "\n完成：删除 #{deleted} 条"
end

run
