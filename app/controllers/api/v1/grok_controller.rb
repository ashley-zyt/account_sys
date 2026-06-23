class Api::V1::GrokController < ApplicationController
  # 获取Grok图片资源（一次只获取一个）
  def images
    # 获取已使用的图片ID列表
    used_image_ids = GrokTask.where.not(grok_image_id: nil).pluck(:grok_image_id)

    # 获取未被使用的图片资源，按id升序排序，取第一个
    grok_image = GrokImageResource
                  .where.not(id: used_image_ids)
                  .order(id: :asc)
                  .first

    if grok_image.blank?
      render json: {
        code: 200,
        msg: '没有可用的图片资源',
        data: nil
      }
      return
    end

    # 获取对应主题的prompts
    theme = Theme.find_by(name: grok_image.theme)
    prompts = theme&.prompts_array || []

    data = {
      id: grok_image.id,
      image_url: grok_image.image_url,
      prompts: prompts
    }

    render json: {
      code: 200,
      msg: 'success',
      data: data
    }
  rescue => e
    render json: { code: 500, msg: "服务器错误: #{e.message}" }, status: :internal_server_error
  end

  # 外部传入 bucket 名和视频文件名，先校验文件存在性，存在则返回 OSS 签名 URL
  def video_url
    bucket_name = params[:bucket].to_s.strip
    filename = params[:filename].to_s.strip

    if bucket_name.blank? || filename.blank?
      render json: { code: 400, msg: '缺少 bucket 或 filename 参数', data: nil }
      return
    end

    access_key_id = ENV['ALIYUN_ACCESS_KEY_ID']
    access_key_secret = ENV['ALIYUN_ACCESS_KEY_SECRET']

    if access_key_id.blank? || access_key_secret.blank?
      render json: { code: 500, msg: 'OSS 凭证未配置', data: nil }, status: :internal_server_error
      return
    end

    # 先校验视频文件在 OSS 中是否存在（HEAD 请求）
    unless oss_object_exists?(bucket_name, filename, access_key_id, access_key_secret)
      render json: { code: 404, msg: '视频文件在 OSS 中不存在', data: nil }
      return
    end

    # 存在则生成签名 URL（1 年有效期）
    signed_url = generate_oss_signed_url(bucket_name, filename, access_key_id, access_key_secret)

    render json: {
      code: 200,
      msg: 'success',
      data: {
        url: signed_url,
        bucket: bucket_name,
        filename: filename
      }
    }
  rescue => e
    render json: { code: 500, msg: "服务器错误: #{e.message}", data: nil }, status: :internal_server_error
  end

  private

  # 校验 OSS 对象是否存在（HEAD 请求，签名基于 Date）
  def oss_object_exists?(bucket_name, key, access_key_id, access_key_secret)
    require 'net/http'
    require 'openssl'
    require 'base64'

    date = Time.now.utc.strftime('%a, %d %b %Y %H:%M:%S GMT')

    # 签名字符串中的 key 使用原始路径（不编码）
    string_to_sign = "HEAD\n\n\n#{date}\n/#{bucket_name}/#{key}"
    signature = Base64.strict_encode64(
      OpenSSL::HMAC.digest('sha1', access_key_secret, string_to_sign)
    ).strip

    # URL 中的 key 需要编码
    encoded_key = URI.encode_www_form_component(key)
    uri = URI.parse("https://#{bucket_name}.oss-cn-hangzhou.aliyuncs.com/#{encoded_key}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    request = Net::HTTP::Head.new(uri.request_uri)
    request['Date'] = date
    request['Authorization'] = "OSS #{access_key_id}:#{signature}"

    response = http.request(request)
    response.code == '200'
  end

  # 生成 OSS GET 签名 URL（签名基于 Expires，1 年有效期）
  def generate_oss_signed_url(bucket_name, key, access_key_id, access_key_secret)
    require 'openssl'
    require 'base64'

    ts = Time.now.to_i + 31536000 # 1年有效期

    # 签名字符串中的 key 使用原始路径（不编码）
    cano_res = "/#{bucket_name}/#{key}"
    sign_string = "GET\n\n\n#{ts}\n#{cano_res}"

    signature = OpenSSL::HMAC.digest('sha1', access_key_secret, sign_string).to_s
    signature = Base64.strict_encode64(signature).strip
    signature = URI.encode_www_form_component(signature)

    # URL 中的 key 需要编码
    encoded_key = URI.encode_www_form_component(key)

    "https://#{bucket_name}.oss-cn-hangzhou.aliyuncs.com/#{encoded_key}?OSSAccessKeyId=#{access_key_id}&Expires=#{ts}&Signature=#{signature}"
  end
end
