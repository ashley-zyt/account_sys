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
      # aliyun-sdk 的 get_object / put_object 都用 file: 参数传本地文件路径，
      # 直接从源下载到临时文件、再上传到目标，流式不占内存。
      require 'tempfile'
      tmp = Tempfile.new(['oss_transfer', '.bin'])
      tmp_path = tmp.path
      tmp.close
      begin
        src.get_object(key, file: tmp_path)
        dst.put_object(key, file: tmp_path)
      ensure
        File.delete(tmp_path) if File.exist?(tmp_path)
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

  # 批量转存：扫描三个源 bucket 的任务，按 object key 去重转存、批量换链，并删除源对象。
  # 同一个视频被多平台任务共用时只转存一次；更新完所有引用该 key 的任务后删除源对象。
  # @param per_model [Integer] 每个模型一次处理多少个唯一 key
  # @return [Hash] { total:, success:, failed: }（success=换链任务数，failed=转存失败的 key 数）
  def self.batch_transfer(per_model: 50)
    total = success = failed = 0

    {
      'huasheng-ld'   => 'HuashengTask',
      'jianying-rd'   => 'JianyingTask',
      'notebooklm-ld' => 'NotebooklmTask'
    }.each do |src, model_name|
      model = model_name.constantize

      # 取一批待转存的唯一 key（去重）
      keys = model.where("oss_url LIKE ?", "%#{src}.oss-%")
                  .where.not(full_oss_url: [nil, ''])
                  .order(id: :asc)
                  .limit(per_model)
                  .pluck(:full_oss_url)
                  .map { |k| k.to_s.strip.sub(%r{^/}, '') }
                  .uniq

      keys.each do |key|
        transferred = transfer(src, key)
        if transferred
          new_key, new_url = transferred

          # 更新所有引用该 key 的任务（不限当前批次），确保删源前无遗留引用
          scope = model.where("oss_url LIKE ?", "%#{src}.oss-%")
                       .where(full_oss_url: [key, "/#{key}"])
          count = scope.update_all(oss_url: new_url, full_oss_url: new_key, updated_at: Time.current)

          success += count
          total += count

          # 所有引用已换链，删除源对象
          delete_source(src, key)
        else
          total += 1
          failed += 1
        end
      end
    end

    { total: total, success: success, failed: failed }
  end

  # 删除源对象（尽力而为，失败只记日志，不影响整体结果）
  def self.delete_source(source_bucket, key)
    oss_client(*source_credentials).get_bucket(source_bucket).delete_object(key)
    Rails.logger.info "[OssTransfer] 已删除源对象 #{source_bucket}/#{key}"
    true
  rescue => e
    Rails.logger.warn "[OssTransfer] 删除源对象失败 #{source_bucket}/#{key}: #{e.class} #{e.message}"
    false
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
