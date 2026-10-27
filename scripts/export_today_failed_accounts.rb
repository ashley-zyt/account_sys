# 导出「今日发布全部失败」的账号及错误信息
#
# 运行（在项目根目录）：
#   bundle exec rails runner scripts/export_today_failed_accounts.rb            # 今天
#   bundle exec rails runner scripts/export_today_failed_accounts.rb 2026-10-27 # 指定日期
#
# 输出：tmp/今日发布失败账号_<日期>_<时间>.xlsx
#
# 规则：
#   - 只统计「发布」日志（publish_channel 非空；采集/养号等日志该字段为 NULL）
#   - 只导出「全部失败」的账号：当天有失败记录、且没有任何成功记录
#   - 一个账号当天执行了多次，会把每次的错误信息都列出（带次数和失败时间）

require "zlib"

date = ARGV[0] ? Date.parse(ARGV[0]) : Time.zone.today
day_start = date.beginning_of_day
day_end   = date.end_of_day

timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
out_path  = Rails.root.join("tmp", "今日发布失败账号_#{date.strftime('%Y%m%d')}_#{timestamp}.xlsx")

HEADERS = %w[
  账号ID
  账号名
  平台
  当前状态
  负责人
  浏览器名
  失败次数
  错误信息(全部)
  最后失败时间
]

# ---------------- 数据组装 ----------------

logs = TaskLog.where.not(publish_channel: nil)
              .where(run_at: day_start..day_end)
              .order(:run_at, :id)

grouped = logs.group_by(&:account_id)

def errors_text(failed_logs)
  failed_logs.each_with_index.map do |log, i|
    t = (log.run_at || log.created_at).strftime('%m-%d %H:%M')
    msg = log.error_msg.presence || '(无错误信息)'
    "[#{i + 1}次 #{t}] #{msg}"
  end.join("\n")
end

rows = []
failed_count_total = 0

grouped.each do |account_id, acct_logs|
  next if account_id.nil?

  failed_logs = acct_logs.select(&:failed?)
  next if failed_logs.empty?           # 今天没有失败记录
  next if acct_logs.any?(&:success?)   # 当天有成功 → 非「全部失败」，跳过

  account = Account.unscoped.find_by(id: account_id)

  status_text =
    if account.nil?
      "不存在"
    elsif account.deleted_at.present?
      "已删除"
    else
      account.status.to_s
    end

  last_failed = failed_logs.max_by { |l| l.run_at || l.created_at }

  rows << [
    [
      account_id,
      account&.account_name,
      account&.platform.to_s,
      status_text,
      account&.operator,
      account&.browser&.profile_name,
      failed_logs.size,
      errors_text(failed_logs),
      (last_failed.run_at || last_failed.created_at).strftime('%Y-%m-%d %H:%M'),
    ],
    false
  ]
  failed_count_total += 1
end

# ---------------- xlsx 生成（纯 Ruby 标准库，无需额外 gem） ----------------

def xml_escape(str)
  str.to_s
     .gsub(/[&<>"']/) { |c| { "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", '"' => "&quot;", "'" => "&apos;" }[c] }
     .gsub(/[\x00-\x08\x0B\x0C\x0E-\x1F]/, "")
end

def col_name(idx)
  s = ""
  idx += 1
  while idx > 0
    idx, rem = (idx - 1).divmod(26)
    s = (65 + rem).chr + s
  end
  s
end

def row_xml(r, cells, bold)
  out = %(<row r="#{r}">)
  cells.each_with_index do |value, ci|
    style = bold ? %( s="1") : ""
    out << %(<c r="#{col_name(ci)}#{r}" t="inlineStr"#{style}><is><t xml:space="preserve">#{xml_escape(value)}</t></is></c>)
  end
  out << %(</row>)
  out
end

def sheet_xml(headers, rows)
  total = rows.size + 1
  xml = %(<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">)
  xml << %(<dimension ref="A1:#{col_name(headers.size - 1)}#{total}"/>)
  xml << %(<sheetData>)
  xml << row_xml(1, headers, true)
  rows.each_with_index { |(cells, bold), i| xml << row_xml(i + 2, cells, bold) }
  xml << %(</sheetData></worksheet>)
  xml
end

def styles_xml
  <<~XML
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
      <fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>
      <fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>
      <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
      <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
      <cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>
    </styleSheet>
  XML
end

def content_types_xml
  <<~XML
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
      <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
      <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
    </Types>
  XML
end

def root_rels_xml
  <<~XML
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
    </Relationships>
  XML
end

def workbook_xml
  <<~XML
    <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
      <sheets><sheet name="发布失败账号" sheetId="1" r:id="rId1"/></sheets>
    </workbook>
  XML
end

def workbook_rels_xml
  <<~XML
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
      <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
    </Relationships>
  XML
end

def write_zip(io, files)
  local_offsets = []

  files.each do |name, data|
    local_offsets << io.pos
    crc = Zlib.crc32(data)

    io.write([0x04034b50].pack("V"))
    io.write([20].pack("v"))
    io.write([0].pack("v"))
    io.write([0].pack("v"))
    io.write([0].pack("v"))
    io.write([0].pack("v"))
    io.write([crc].pack("V"))
    io.write([data.bytesize].pack("V"))
    io.write([data.bytesize].pack("V"))
    io.write([name.bytesize].pack("v"))
    io.write([0].pack("v"))
    io.write(name)
    io.write(data)
  end

  cd_offset = io.pos

  files.each_with_index do |(name, data), i|
    crc = Zlib.crc32(data)

    io.write([0x02014b50].pack("V"))
    io.write([20].pack("v"))
    io.write([20].pack("v"))
    io.write([0].pack("v"))
    io.write([0].pack("v"))
    io.write([0].pack("v"))
    io.write([0].pack("v"))
    io.write([crc].pack("V"))
    io.write([data.bytesize].pack("V"))
    io.write([data.bytesize].pack("V"))
    io.write([name.bytesize].pack("v"))
    io.write([0].pack("v"))
    io.write([0].pack("v"))
    io.write([0].pack("v"))
    io.write([0].pack("v"))
    io.write([0].pack("V"))
    io.write([local_offsets[i]].pack("V"))
    io.write(name)
  end

  cd_size = io.pos - cd_offset

  io.write([0x06054b50].pack("V"))
  io.write([0].pack("v"))
  io.write([0].pack("v"))
  io.write([files.size].pack("v"))
  io.write([files.size].pack("v"))
  io.write([cd_size].pack("V"))
  io.write([cd_offset].pack("V"))
  io.write([0].pack("v"))
end

# ---------------- 写出 xlsx ----------------

parts = {
  "[Content_Types].xml"        => content_types_xml,
  "_rels/.rels"                => root_rels_xml,
  "xl/workbook.xml"            => workbook_xml,
  "xl/_rels/workbook.xml.rels" => workbook_rels_xml,
  "xl/styles.xml"              => styles_xml,
  "xl/worksheets/sheet1.xml"   => sheet_xml(HEADERS, rows)
}

File.open(out_path, "wb") { |f| write_zip(f, parts) }

puts "=" * 70
puts "日期：#{date}"
puts "当天发布日志数：#{logs.size}"
puts "全部失败（含多账号）账号数：#{failed_count_total}"
puts "文件路径：#{out_path}"
puts "=" * 70
