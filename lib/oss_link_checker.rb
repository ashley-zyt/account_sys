# 检查系统内所有涉及 OSS 的链接：源文件是否存在。
#   - 不存在 → 标记「失效」，由调用方删除对应记录（避免错误分配）
#   - 存在   → 重新生成签名 URL（有效期 = 当前时间 + 1 年）
#
# 检查走 OSS SDK 的 object_exists?（bucket + key 维度），绝不用 HTTP HEAD 探签名 URL：
#   签名 URL 过期后 HEAD 会返回 403/404，会把「文件还在、只是签名过期」误判成「文件不存在」导致误删。
#
# 用法：
#   results = OssLinkChecker.run(confirm: false)   # 只扫描
#   results = OssLinkChecker.run(confirm: true)    # 扫描 + 删除失效 + 续期存在
module OssLinkChecker
  OSS_ENDPOINT = 'https://oss-cn-hangzhou.aliyuncs.com'.freeze
  REGION = 'cn-hangzhou'.freeze
  EXPIRE_SECONDS = 31536000 # 1 年

  # 检查目标清单：
  #   model     资源表名
  #   url_field 存签名 URL 的字段（续期时写回这个字段）
  #   key_field 存纯 object key 的字段（可选，url 为空时用它补 key）
  #   bucket    为 nil 表示从 URL host 解析，否则用该常量
  TARGETS = [
    { model: 'MoveTask',       url_field: 'oss_url',     key_field: nil,            bucket: nil },
    { model: 'HunjianTask',    url_field: 'oss_url',     key_field: 'full_oss_url', bucket: nil },
    { model: 'JianyingTask',   url_field: 'oss_url',     key_field: 'full_oss_url', bucket: 'jianying-rd' },
    { model: 'HuashengTask',   url_field: 'oss_url',     key_field: 'full_oss_url', bucket: 'huasheng-ld' },
    { model: 'NotebooklmTask', url_field: 'oss_url',     key_field: 'full_oss_url', bucket: 'notebooklm-ld' },
    { model: 'OperationTask',  url_field: 'oss_url',     key_field: nil,            bucket: 'operation-viodes' },
    { model: 'MoveVideo',      url_field: 'raw_oss_url', key_field: nil,            bucket: nil }
  ].freeze

  class << self
    # 统一入口。扫描所有目标，返回结构化结果；confirm=true 时执行「删除失效 + 续期存在」。
    # @return [Hash] { missing:, refreshable:, skipped:, error:, deleted:, refreshed: }
    def run(confirm: false)
      results = { missing: [], refreshable: [], skipped: [], error: [], deleted: 0, refreshed: 0 }

      if credentials_configured?
        TARGETS.each { |target| scan_model(target, results) }
      else
        puts '⚠️ 未配置 OSS 凭证（ALIYUN_ACCESS_KEY_ID / ALIYUN_ACCESS_KEY_SECRET），无法检查'
        return results
      end

      if confirm
        results[:deleted]   = delete_missing(results[:missing])
        results[:refreshed] = refresh_urls(results[:refreshable])
      end

      results
    end

    private

    # 扫描单张表的全部记录，按检查结果分桶
    def scan_model(target, results)
      model = target[:model].safe_constantize
      return unless model

      model.find_each do |record|
        bucket, key = resolve_bucket_key(record, target)

        if bucket.blank? || key.blank?
          results[:skipped] << { model: target[:model], id: record.id, reason: '无法解析 bucket/key' }
          next
        end

        status = check_object(bucket, key)
        case status[0]
        when :missing
          results[:missing] << entry(target, record, bucket, key)
        when :exists
          results[:refreshable] << entry(target, record, bucket, key)
        else
          results[:error] << { model: target[:model], id: record.id, reason: status[1].to_s }
        end
      end
    end

    def entry(target, record, bucket, key)
      { model: target[:model], url_field: target[:url_field], id: record.id, bucket: bucket, key: key }
    end

    # 解析 bucket + key：
    #   优先用 url 字段（签名 URL，从 host/path 解析）；
    #   url 空或解析不出 key 时，用 key_field（纯 key）+ 常量 bucket 兜底。
    def resolve_bucket_key(record, target)
      url = record.public_send(target[:url_field]).to_s.strip
      bucket = nil
      key = nil

      bucket, key = parse_oss_url(url) if url.present?

      key = record.public_send(target[:key_field]).to_s.strip if key.blank? && target[:key_field].present?
      bucket = target[:bucket] if bucket.blank? && target[:bucket].present?

      [bucket, key]
    end

    # 从 OSS URL 解析 bucket 与 key（兼容签名 URL，query 参数忽略）
    def parse_oss_url(url)
      uri = URI.parse(url.to_s)
      bucket = uri.host.to_s.split('.').first
      key = uri.path.to_s.sub(%r{\A/}, '')
      begin
        key = URI.decode_www_form_component(key)
      rescue StandardError
        # 解码失败则用原始 path
      end
      [bucket, key]
    rescue StandardError
      [nil, nil]
    end

    # 检查对象是否存在，返回 [:exists] / [:missing] / [:error, msg]
    def check_object(bucket, key)
      exists = oss_client.get_bucket(bucket).object_exists?(key)
      exists ? [:exists] : [:missing]
    rescue => e
      [:error, e.message]
    end

    def credentials_configured?
      ENV['ALIYUN_ACCESS_KEY_ID'].present? && ENV['ALIYUN_ACCESS_KEY_SECRET'].present?
    end

    def oss_client
      @oss_client ||= begin
        require 'aliyun/oss'
        Aliyun::OSS::Client.new(
          endpoint: OSS_ENDPOINT,
          access_key_id: ENV['ALIYUN_ACCESS_KEY_ID'],
          access_key_secret: ENV['ALIYUN_ACCESS_KEY_SECRET']
        )
      end
    end

    # 批量删除失效记录（只删记录，task_log/TaskAssignment 等历史保留）
    def delete_missing(entries)
      total = 0
      entries.group_by { |e| e[:model] }.each do |model_name, ents|
        model = model_name.safe_constantize
        next unless model
        total += model.where(id: ents.map { |e| e[:id] }).delete_all
      end
      total
    end

    # 续期：重新生成 1 年签名的 URL 写回 url_field
    def refresh_urls(entries)
      refreshed = 0
      entries.each do |e|
        model = e[:model].safe_constantize
        next unless model
        new_url = sign_url(e[:bucket], e[:key], EXPIRE_SECONDS)
        next if new_url.blank?
        model.where(id: e[:id]).update_all(e[:url_field] => new_url)
        refreshed += 1
      end
      refreshed
    end

    # OSS V1 GET 签名 URL
    def sign_url(bucket, key, expires_seconds)
      require 'base64'
      require 'openssl'
      access_key_id = ENV['ALIYUN_ACCESS_KEY_ID']
      access_key_secret = ENV['ALIYUN_ACCESS_KEY_SECRET']
      return nil if access_key_id.blank? || access_key_secret.blank?

      expires = (Time.now.to_i + expires_seconds).to_s
      string_to_sign = "GET\n\n\n#{expires}\n/#{bucket}/#{key}"
      signature = Base64.strict_encode64(
        OpenSSL::HMAC.digest('sha1', access_key_secret, string_to_sign)
      ).strip

      encoded_key = key.split('/').map { |seg| percent_encode(seg) }.join('/')
      "https://#{bucket}.oss-#{REGION}.aliyuncs.com/#{encoded_key}?OSSAccessKeyId=#{access_key_id}&Expires=#{expires}&Signature=#{percent_encode(signature)}"
    end

    def percent_encode(str)
      URI.encode_www_form_component(str.to_s).gsub('+', '%20')
    end
  end
end
