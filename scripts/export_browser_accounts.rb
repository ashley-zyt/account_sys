# 导出：指纹浏览器 → 代理(proxy_host) → 运营机器 → 正常账号/平台 → 近三次浏览量是否全为0
#
# 运行方式（在项目根目录 d:\ashly\account_sys 下执行）：
#   bin/rails runner scripts/export_browser_accounts.rb
#   或  bundle exec rails runner scripts/export_browser_accounts.rb
#
# 输出：tmp/browser_accounts_export_<时间戳>.xlsx（真正的 Excel 文件）
# 说明：不加分隔行；每个「指纹浏览器」的第一条记录整行加粗，用于区分不同浏览器。
#       （表头行同样加粗。）

require "zlib"

timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
out_path  = Rails.root.join("tmp", "browser_accounts_export_#{timestamp}.xlsx")

HEADERS = %w[
  指纹浏览器名
  proxy_host(代理)
  运营机器
  账号名
  平台
  近三次浏览量是否全为0
]

# ---------------- 数据相关 ----------------

# 近三次浏览量：取该账号最近 3 条发文记录（按 post_date 倒序），判断是否全部为 0。
def recent_views_zero_label(account)
  recent = account.post_stats
                  .order(post_date: :desc, id: :desc)
                  .limit(3)
                  .pluck(:views_count)

  return "无记录" if recent.empty?
  recent.all? { |v| v.to_i == 0 } ? "是" : "否"
end

# ---------------- xlsx 生成（纯 Ruby 标准库，无需额外 gem） ----------------

def xml_escape(str)
  str.to_s
     .gsub(/[&<>"']/) { |c| { "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", '"' => "&quot;", "'" => "&apos;" }[c] }
     .gsub(/[\x00-\x08\x0B\x0C\x0E-\x1F]/, "")
end

# 0 => A, 1 => B, ...
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

# rows: [[cells_array, bold_bool], ...]
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
      <sheets><sheet name="导出" sheetId="1" r:id="rId1"/></sheets>
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

# 极简 ZIP 写出（stored 方式，不依赖 rubyzip 等第三方 gem）
def write_zip(io, files)
  local_offsets = []

  files.each do |name, data|
    local_offsets << io.pos
    crc = Zlib.crc32(data)

    io.write([0x04034b50].pack("V"))   # local file header signature
    io.write([20].pack("v"))           # version needed
    io.write([0].pack("v"))            # flags
    io.write([0].pack("v"))            # method: 0 = stored
    io.write([0].pack("v"))            # mod time
    io.write([0].pack("v"))            # mod date
    io.write([crc].pack("V"))
    io.write([data.bytesize].pack("V")) # compressed size
    io.write([data.bytesize].pack("V")) # uncompressed size
    io.write([name.bytesize].pack("v"))
    io.write([0].pack("v"))            # extra len
    io.write(name)
    io.write(data)
  end

  cd_offset = io.pos

  files.each_with_index do |(name, data), i|
    crc = Zlib.crc32(data)

    io.write([0x02014b50].pack("V"))   # central directory header signature
    io.write([20].pack("v"))           # version made by
    io.write([20].pack("v"))           # version needed
    io.write([0].pack("v"))            # flags
    io.write([0].pack("v"))            # method
    io.write([0].pack("v"))            # mod time
    io.write([0].pack("v"))            # mod date
    io.write([crc].pack("V"))
    io.write([data.bytesize].pack("V"))
    io.write([data.bytesize].pack("V"))
    io.write([name.bytesize].pack("v"))
    io.write([0].pack("v"))            # extra len
    io.write([0].pack("v"))            # comment len
    io.write([0].pack("v"))            # disk number start
    io.write([0].pack("v"))            # internal attrs
    io.write([0].pack("V"))            # external attrs
    io.write([local_offsets[i]].pack("V"))
    io.write(name)
  end

  cd_size = io.pos - cd_offset

  io.write([0x06054b50].pack("V"))     # end of central directory signature
  io.write([0].pack("v"))
  io.write([0].pack("v"))
  io.write([files.size].pack("v"))
  io.write([files.size].pack("v"))
  io.write([cd_size].pack("V"))
  io.write([cd_offset].pack("V"))
  io.write([0].pack("v"))              # comment len
end

# ---------------- 组装数据 ----------------

rows = []
browser_ids = []
prev_browser_id = Object.new

Account.active
       .includes(:browser)
       .order(:browser_id, :account_name)
       .each do |account|
  browser = account.browser
  bold = (account.browser_id != prev_browser_id) # 新浏览器出现的第一行加粗

  rows << [
    [
      browser&.profile_name,
      browser&.proxy_host,
      browser&.machine_ip,
      account.account_name,
      account.platform.to_s,
      recent_views_zero_label(account)
    ],
    bold
  ]

  browser_ids << account.browser_id unless account.browser_id.nil?
  prev_browser_id = account.browser_id
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

puts "导出完成：共 #{rows.size} 个正常账号，涉及 #{browser_ids.uniq.size} 个指纹浏览器"
puts "文件路径：#{out_path}"
