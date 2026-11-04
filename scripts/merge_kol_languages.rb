# KOL 语言合并脚本：把 languages 表 50 条历史脏数据合并为 42 条标准语言。
#
# 处理规则（人工确认过的合并方案）：
#   1. 改名为标准名：中文→简体中文、英文→英语、日文→日语、韩文→韩语
#   2. 别名合并：阿拉伯文→阿拉伯语、西班牙文→西班牙语、中文/英文→简体中文
#   3. 代码名转中文：kan→卡纳达语、zhs/cmn→简体中文、zht→繁体中文、
#      hbs→塞尔维亚-克罗地亚语、som→索马里语、amh→阿姆哈拉语、mya→缅甸语、
#      fas→波斯语、pus→普什图语、uzb→乌兹别克语
#   4. 其余语言不改名不合并（含 荷兰文 保留原名）
#
# 引用处理：
#   - kols.language_id、message_template_versions.language_id 重新指向保留记录
#   - 同一模板合并后出现同语言两条版本时，保留 updated_at 最新一条，删除旧条
#   - 被合并的语言记录最后删除
#
# 用法（服务器上执行）：
#   预览： bundle exec rails runner scripts/merge_kol_languages.rb
#   执行： EXEC=1 bundle exec rails runner scripts/merge_kol_languages.rb

MERGE_MAP = {
  # 改名为标准名
  '中文'     => '简体中文',
  '英文'     => '英语',
  '日文'     => '日语',
  '韩文'     => '韩语',
  # 别名合并
  '中文/英文' => '简体中文',
  '阿拉伯文' => '阿拉伯语',
  '西班牙文' => '西班牙语',
  # 代码名转中文名
  'kan' => '卡纳达语',
  'zhs' => '简体中文',
  'zht' => '繁体中文',
  'hbs' => '塞尔维亚-克罗地亚语',
  'som' => '索马里语',
  'amh' => '阿姆哈拉语',
  'mya' => '缅甸语',
  'fas' => '波斯语',
  'pus' => '普什图语',
  'uzb' => '乌兹别克语',
  'cmn' => '简体中文'
}.freeze

exec_mode = ENV['EXEC'] == '1'
total_before = Language.count

# 按标准名分组
groups = Hash.new { |h, k| h[k] = [] }
Language.find_each { |l| groups[MERGE_MAP.fetch(l.name, l.name)] << l }

deleted_langs = 0
moved_kols    = 0
removed_mtv   = 0
conflicts     = []

groups.sort.each do |canonical, langs|
  next if langs.size == 1 && langs.first.name == canonical # 无需处理

  # 保留记录：已有标准名的优先，否则取 id 最小的
  primary = langs.find { |l| l.name == canonical } || langs.min_by(&:id)
  dups    = langs - [primary]

  puts "[分组] #{canonical}：保留 #{primary.id}:#{primary.name}，" \
       "合并 #{dups.map { |l| "#{l.id}:#{l.name}" }.join('、')}"

  # 模板版本冲突检测：dup 的模板版本与 primary 已有同模板版本撞唯一性
  dups.each do |dup|
    MessageTemplateVersion.where(language_id: dup.id).find_each do |ver|
      clash = MessageTemplateVersion.find_by(message_template_id: ver.message_template_id, language_id: primary.id)
      if clash
        keep, drop = [ver, clash].sort_by { |v| v.updated_at || v.created_at }.reverse
        conflicts << "模板##{ver.message_template_id} 语言「#{canonical}」：保留 #{keep.id}（#{keep.updated_at}），删除 #{drop.id}"
        drop.destroy! if exec_mode
        removed_mtv += 1
      end
    end
  end

  next unless exec_mode

  # 改名保留记录 + 引用重指向 + 删除被合并记录
  primary.update!(name: canonical) if primary.name != canonical
  dups.each do |dup|
    moved_kols += Kol.where(language_id: dup.id).update_all(language_id: primary.id)
    MessageTemplateVersion.where(language_id: dup.id).update_all(language_id: primary.id)
    dup.destroy!
    deleted_langs += 1
  end
end

if exec_mode
  puts '=' * 50
  puts "完成：删除语言 #{deleted_langs} 条，迁移 KOL #{moved_kols} 个，清理重复模板版本 #{removed_mtv} 条"
  puts "当前语言总数：#{Language.count}"
  conflicts.each { |c| puts "  冲突处理：#{c}" } if conflicts.any?
else
  puts '=' * 50
  puts '--- 预览模式（加 EXEC=1 实际执行）---'
  puts "语言 #{total_before} 条 -> #{groups.size} 条，将删除 #{total_before - groups.size} 条"
  puts "模板版本冲突 #{conflicts.size} 处："
  conflicts.each { |c| puts "  #{c}" }
end
