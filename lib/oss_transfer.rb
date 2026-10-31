# OSS 跨账号转存：TWO 账号源 bucket → 主账号目标 bucket。
#
# 场景：机器端下载 TWO 账号 bucket（jianying-rd / notebooklm-ld / huasheng-ld）
#       的视频容易超时，在「分发任务」时把对象转存到主账号同名 + "-videos" 的
#       新 bucket，任务改用主账号签名 URL。
#
# 说明：
#   - 源凭证：TWO 账号（与各模型/控制器里硬编码的 key 一致）。
#   - 目标凭证：主账号 ENV（ALIYUN_ACCESS_KEY_ID / ALIYUN_ACCESS_KEY_SECRET）。
#   - OSS bucket 名全局唯一，源 bucket 已被 TWO 账号占用，主账号无法同名，
#     故目标统一用「原名 + -videos」后缀。
#   - 只读源、只写目标，源对象一个都不会删除。
class OssTransfer
  OSS_ENDPOINT = 'https://oss-cn-hangzhou.aliyuncs.com'.freeze
  REGION = 'cn-hangzhou'.freeze
  SIGNED_URL_TTL = 31_536_000 # 1 年

  # 源 bucket（TWO 账号）→ 目标 bucket（主账号）
  BUCKET_MAP = {
    'huasheng-ld'   => 'huasheng-ld-videos',
    'jianying-rd'   => 'jianying-rd-videos',
    'notebooklm-ld' => 'notebooklm-ld-videos'
  }.freeze

  # 源凭证：TWO 账号（与各模型/控制器硬编码一致）
  SOURCE_ACCESS_KEY_ID = 'gZL8z938T19mSUHf'.freeze
  SOURCE_ACCESS_KEY_SECRET = 'A9fSDa9cH5YAExpEUR4QSizkFQEcrS'.freeze

  # 转存对象到目标 bucket，成功返回 [new_key, signed_url]，失败返回 nil。
  # 目标已存在则跳过（幂等），只读源、只写目标，不删除源对象。
  def self.transfer(source_bucket, object_key, expires_seconds = SIGNED_URL_TTL)
    dest_bucket = BUCKET_MAP[source_bucket.to_s]
    return nil if dest_bucket.blank? || object_key.blank?

    key = object_key.to_s.sub(%r{^/}, '')

    src = oss_client(*source_credentials).get_bucket(source_bucket)
    dst = oss_client(*dest_credentials).get_bucket(dest_bucket)

    unless dst.object_exists?(key)
      obj = src.get_object(key)
      content = obj.respond_to?(:body) ? obj.body : (obj.respond_to?(:read) ? obj.read : obj)

      # aliyun-sdk 的 put_object 用 file: 参数传本地文件路径（不支持 content:），
      # 故先把内容落临时文件再上传。
      require 'tempfile'
      tmp = Tempfile.new(['oss_transfer', '.bin'])
      begin
        tmp.binmode
        tmp.write(content)
        tmp.flush
        dst.put_object(key, file: tmp.path)
      ensure
        tmp.close!
      end
    end

    [key, dest_sign_url(dest_bucket, key, expires_seconds)]
  rescue => e
    Rails.logger.error "[OssTransfer] 转存失败 #{source_bucket}/#{object_key}: #{e.class} #{e.message}"
    nil
  end

  # 目标 bucket 主账号 V1 GET 签名 URL
  def self.dest_sign_url(dest_bucket, key, expires_seconds = SIGNED_URL_TTL)
    return nil if key.blank?
    require 'openssl'
    require 'base64'

    key = key.sub(%r{^/}, '')
    expires = (Time.now.utc.to_i + expires_seconds).to_s
    string_to_sign = "GET\n\n\n#{expires}\n/#{dest_bucket}/#{key}"
    signature = Base64.strict_encode64(
      OpenSSL::HMAC.digest('sha1', dest_secret.to_s, string_to_sign)
    ).strip
    encoded_key = key.split('/').map { |seg| percent_encode(seg) }.join('/')

    "https://#{dest_bucket}.oss-#{REGION}.aliyuncs.com/#{encoded_key}?" \
      "OSSAccessKeyId=#{dest_key_id}" \
      "&Expires=#{expires}" \
      "&Signature=#{percent_encode(signature)}"
  end

  # 判断 url 是否指向源 bucket，是则转存到目标 bucket 并返回 [new_key, new_url]；否则返回 nil。
  # 用于「下发/发布」前的兜底：库里旧数据的 oss_url 仍是源 bucket 时，现场转存换链。
  # @param url [String] 任务里存的对象 URL（含 host，可解析 bucket）
  # @param key [String] 纯 object key（full_oss_url）；为空时从 url 解析
  def self.transfer_if_source(url, key = nil)
    return nil if url.blank?

    bucket = bucket_from_url(url)
    return nil unless BUCKET_MAP.key?(bucket)

    key = key.presence || key_from_url(url)
    return nil if key.blank?

    transfer(bucket, key)
  end

  # 从对象 URL 解析 bucket 名（host 第一段）
  def self.bucket_from_url(url)
    require 'uri'
    URI.parse(url.to_s).host.to_s.split('.').first
  rescue StandardError
    nil
  end

  # 从对象 URL 解析 object key（path 去掉前导 / 并 URL 解码）
  def self.key_from_url(url)
    require 'uri'
    key = URI.parse(url.to_s).path.to_s.sub(%r{\A/}, '')
    URI.decode_www_form_component(key)
  rescue StandardError
    nil
  end

  # 源凭证：TWO 账号（硬编码）
  def self.source_credentials
    [SOURCE_ACCESS_KEY_ID, SOURCE_ACCESS_KEY_SECRET]
  end

  # 目标凭证：主账号 ENV
  def self.dest_credentials
    [ENV['ALIYUN_ACCESS_KEY_ID'], ENV['ALIYUN_ACCESS_KEY_SECRET']]
  end

  def self.dest_key_id
    ENV['ALIYUN_ACCESS_KEY_ID']
  end

  def self.dest_secret
    ENV['ALIYUN_ACCESS_KEY_SECRET']
  end

  def self.percent_encode(str)
    URI.encode_www_form_component(str.to_s).gsub('+', '%20')
  end

  def self.oss_client(access_key_id, access_key_secret)
    @oss_clients ||= {}
    @oss_clients[[access_key_id, access_key_secret]] ||= begin
      require 'aliyun/oss'
      Aliyun::OSS::Client.new(
        endpoint: OSS_ENDPOINT,
        access_key_id: access_key_id,
        access_key_secret: access_key_secret
      )
    end
  end
end
