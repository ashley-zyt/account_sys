# KOL 批量导入服务（Excel .xlsx）
#
# 支持：
#   - 生成导入模板（write_xlsx）：固定列 + 动态「消息变量」列
#   - 解析上传的 xlsx（roo）
#   - 校验 + 查重 + 同名聚合预览
#   - 确认导入（创建 Kol + KolContact + 变量值）
#
# 模板列（一行 = 一个 KOL 的一个联系方式；同名 KOL 自动聚合到同一 KOL）：
#   固定列：KOL名称 | 所属领域 | 归属人 | 国家/地区 | 使用语言 | 粉丝量级 | 平台 | 昵称/账号 | 主页链接 | 可发私信 | 优先级 | 备注
#   变量列（动态，来自 MessageVariable）：如 称呼/姓名(name) | 邮箱(email) | 公司/品牌(company)
#     - name 变量留空时自动 = KOL名称；填了则用填写的值（可自定义称呼）
class KolImporter
  BASE_COLUMNS = %w[KOL名称 所属领域 归属人 国家/地区 使用语言 粉丝量级 平台 昵称/账号 主页链接 可发私信 优先级 备注].freeze

  # 平台名别名 → 枚举 key（兼容中英文常见写法）
  PLATFORM_ALIASES = {
    "facebook" => "facebook", "脸书" => "facebook", "fb" => "facebook",
    "twitter"  => "twitter",  "推特" => "twitter",  "x"  => "twitter",
    "tiktok"   => "tiktok",   "抖音" => "tiktok",
    "youtube"  => "youtube",  "油管" => "youtube",  "yt" => "youtube",
    "instagram" => "instagram", "ins" => "instagram", "ig" => "instagram",
    "email"    => "email",    "邮箱" => "email",
    "telegram" => "telegram", "tg"  => "telegram",
    "whatsapp" => "whatsapp", "wa"  => "whatsapp"
  }.freeze

  TRUE_VALUES = %w[是 1 true yes y t 对 有效].freeze

  class << self
    # 变量列（动态，来自全局变量字典 MessageVariable）
    # 返回 [{ identifier:, label: }]，label 用于模板列头
    def variable_columns
      MessageVariable.order(:id).map do |v|
        { identifier: v.identifier, label: "#{v.name}(#{v.identifier})" }
      end
    end

    def all_columns
      BASE_COLUMNS + variable_columns.map { |v| v[:label] }
    end

    # 生成导入模板 xlsx 到指定路径
    def generate_template(file_path)
      require "write_xlsx"
      workbook = WriteXLSX.new(file_path)
      ws = workbook.add_worksheet("KOL导入模板")

      header = workbook.add_format(bold: 1, bg_color: "#dbeafe", border: 1, align: "center")
      cols = all_columns
      ws.set_column(0, cols.size - 1, 16)

      cols.each_with_index { |c, i| ws.write(0, i, c, header) }

      example = ["hanfuxiu", "文旅", "杜维", "美国", "英文", "0万-10万",
                 "facebook", "hanfuxiu", "https://www.facebook.com/profile.php?id=123", "是", "0", "示例行，请删除"]
      # 变量列示例留空（name 自动取 KOL名称，其余可选）
      example += [""] * variable_columns.size
      example.each_with_index { |v, i| ws.write(1, i, v) }

      workbook.close
      file_path
    end

    # 解析 xlsx，返回行数组（每行 { row_no:, raw: [String] }，跳过表头和空行）
    def parse(file_path)
      require "roo"
      xlsx = Roo::Spreadsheet.open(file_path)
      sheet = xlsx.sheet(0)

      rows = []
      sheet.each_with_index do |row, idx|
        next if idx == 0 # 跳过表头
        cells = row.map { |c| c.to_s.strip }
        next if cells.all?(&:blank?)
        rows << { row_no: idx + 1, raw: cells }
      end
      rows
    end

    # 校验所有行：逐行校验 + 文件内部查重 + 与现有数据查重
    # 返回 { valid: [Hash], invalid: [{ row_no:, error: }] }
    def validate_all(rows)
      valid = []
      invalid = []
      seen_urls = {}

      rows.each do |r|
        res = validate_row(r[:raw])
        unless res[:ok]
          invalid << { row_no: r[:row_no], error: res[:error] }
          next
        end
        d = res[:data]

        if seen_urls[d[:url]]
          invalid << { row_no: r[:row_no], error: "主页链接与第 #{seen_urls[d[:url]]} 行重复" }
          next
        end

        existing = KolContact.where.not(kol_id: nil)
                             .where("url = ? OR (nickname <> '' AND nickname = ?)", d[:url], d[:nickname])
                             .first
        if existing
          invalid << { row_no: r[:row_no], error: "主页链接/昵称已存在于 KOL「#{existing.kol&.name}」" }
          next
        end

        seen_urls[d[:url]] = r[:row_no]
        valid << d
      end

      { valid: valid, invalid: invalid }
    end

    # 确认导入：按「KOL名称」聚合，同名合并为同一 KOL 的多个联系方式
    # 返回 { created: Integer, contacts: Integer, failed: [{ name:, error: }] }
    def import!(valid_rows)
      grouped = valid_rows.group_by { |d| d[:name] }
      created = 0
      contacts = 0
      failed = []

      grouped.each do |name, items|
        first = items.first
        begin
          kol = build_kol(first)
          items.each do |it|
            kol.kol_contacts.create!(
              platform: it[:platform],
              nickname: it[:nickname].presence,
              url: it[:url],
              priority: it[:priority],
              messaging_enabled: it[:messaging_enabled]
            )
            contacts += 1
          end

          # 写入变量：name 变量留空则自动用 KOL 名称，其余按列填写
          write_variables(kol, first[:variables])
          created += 1
        rescue => e
          failed << { name: name, error: e.message }
        end
      end

      { created: created, contacts: contacts, failed: failed }
    end

    private

    # 校验一行，返回 { ok: true, data: {...} } 或 { ok: false, error: "..." }
    def validate_row(cells)
      name     = cell(cells, 0)
      domain   = cell(cells, 1)
      owner    = cell(cells, 2)
      country  = cell(cells, 3)
      lang     = cell(cells, 4)
      tier     = cell(cells, 5)
      platform = cell(cells, 6)
      nickname = cell(cells, 7)
      url      = cell(cells, 8)
      dm       = cell(cells, 9)
      priority = cell(cells, 10)
      notes    = cell(cells, 11)

      return fail_row("KOL名称不能为空") if name.blank?
      return fail_row("所属领域不能为空") if domain.blank?
      return fail_row("归属人不能为空") if owner.blank?
      return fail_row("平台不能为空") if platform.blank?
      return fail_row("主页链接不能为空") if url.blank?
      return fail_row("归属人「#{owner}」不在运营人员列表") unless Account::OPERATORS.include?(owner)

      platform_key = PLATFORM_ALIASES[platform.downcase]
      return fail_row("平台「#{platform}」不合法") if platform_key.nil?
      return fail_row("平台「#{platform}」未在系统平台枚举中") unless KolContact.platforms.key?(platform_key)

      tier_min, tier_max = parse_tier(tier)
      return fail_row("粉丝量级「#{tier}」不合法") if tier.present? && tier_min.nil? && tier_max.nil?

      # 变量列（BASE_COLUMNS.size 之后），只收集非空的
      variables = {}
      variable_columns.each_with_index do |vc, i|
        val = cell(cells, BASE_COLUMNS.size + i)
        variables[vc[:identifier]] = val if val.present?
      end

      {
        ok: true,
        data: {
          name: name, domain_name: domain, owner: owner, country: country.presence,
          language_name: lang.presence, tier_min: tier_min, tier_max: tier_max,
          platform: platform_key, nickname: nickname, url: url,
          messaging_enabled: parse_bool(dm),
          priority: priority.present? ? priority.to_i : 0,
          notes: notes.presence,
          variables: variables
        }
      }
    end

    def cell(cells, idx)
      (cells[idx] || "").to_s.strip
    end

    def fail_row(msg)
      { ok: false, error: msg }
    end

    def parse_bool(v)
      TRUE_VALUES.include?(v.to_s.strip.downcase)
    end

    # 粉丝量级：支持 "0万-10万" 标签，也支持 "0,100000" 区间格式
    def parse_tier(str)
      return [nil, nil] if str.blank?
      s = str.to_s.strip
      tier = Kol::FOLLOWER_TIERS.find { |t| t[:label] == s }
      return [tier[:min], tier[:max]] if tier
      if s.include?(",")
        min_s, max_s = s.split(",", 2)
        return [min_s.present? ? min_s.to_i : nil, max_s.present? ? max_s.to_i : nil]
      end
      [nil, nil]
    end

    def build_kol(d)
      domain = Domain.find_or_create_by_name(d[:domain_name].strip)
      language = d[:language_name].present? ? Language.find_or_create_by_name(d[:language_name].strip) : nil

      Kol.create!(
        name: d[:name],
        domain: domain,
        language: language,
        owner: d[:owner],
        country: d[:country],
        follower_min: d[:tier_min],
        follower_max: d[:tier_max],
        notes: d[:notes],
        status: :reserved # 导入默认「未开始」，不自动触达
      )
    end

    # 写入变量值：name 变量留空则自动 = KOL 名称，其余按模板列填写
    def write_variables(kol, variables)
      vars = variables || {}
      kol.set_variable!("name", vars["name"].presence || kol.name)
      vars.each do |key, value|
        kol.set_variable!(key, value) unless key == "name"
      end
    end
  end
end
