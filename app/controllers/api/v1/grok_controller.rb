class Api::V1::GrokController < ApplicationController
  # 外部 API 调用，关闭 CSRF 校验
  skip_forgery_protection

  include OssSignedUrl

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
    prompts = theme&.prompts_array.sample(5) || []

    remark = theme&.remark.to_s
    resolution = if remark.include?('720')
                  '720'
                elsif remark.include?('480')
                  '480'
                else
                  '720'
                end

    data = {
      id: grok_image.id,
      image_url: grok_image.image_url,
      prompts: prompts,
      theme: grok_image.theme,
      resolution: resolution,
    }

    render json: {
      code: 200,
      msg: 'success',
      data: data
    }
  rescue => e
    render json: { code: 500, msg: "服务器错误: #{e.message}" }, status: :internal_server_error
  end

  # 接收保存生成的视频信息，五个平台各创建一条 grok_task 记录
  def save_video
    theme = params[:theme].to_s.strip
    video_url = params[:video_url].to_s.strip
    prompt = params[:prompt].to_s.strip
    grok_image_id = params[:grok_image_id].presence

    if theme.blank? || video_url.blank? || prompt.blank?
      render json: { code: 400, msg: '缺少必要参数 (theme, video_url, prompt)', data: nil }
      return
    end

    # 校验图片资源是否存在
    grok_image = GrokImageResource.find_by(id: grok_image_id)
    if grok_image.blank?
      render json: { code: 404, msg: "图片资源不存在: grok_image_id=#{grok_image_id}", data: nil }
      return
    end

    # 校验主题配置存在且可取到候选标题
    theme_config = Theme.find_by(name: theme)
    candidate_titles = theme_config&.titles_array || []
    if candidate_titles.empty?
      render json: { code: 400, msg: "主题 #{theme} 没有配置候选标题，无法生成任务", data: nil }
      return
    end

    # 五个平台各创建一条，title 从主题 titles 中随机挑选
    platforms = GrokTask.platforms.keys # ["facebook", "twitter", "tiktok", "youtube", "instagram"]
    created_tasks = []

    image_name = grok_image&.image_name

    ActiveRecord::Base.transaction do
      platforms.each do |platform|
        title = candidate_titles.sample
        if title.include?('****') && image_name.present?
          title = title.gsub('****', image_name)
        end

        task_attrs = {
          theme: theme,
          video_url: video_url,
          prompt: prompt,
          grok_image_id: grok_image_id,
          platform: platform,
          status: :pending
        }

        if platform == 'youtube'
          task_attrs[:title] = title[0, 100]
          task_attrs[:description] = title[100..-1]
        else
          task_attrs[:title] = title
        end

        created_tasks << GrokTask.create!(task_attrs)
      end
    end

    render json: {
      code: 200,
      msg: 'success',
      data: {
        created_count: created_tasks.size,
        platforms: platforms,
        task_ids: created_tasks.map(&:id)
      }
    }
  rescue => e
    render json: { code: 500, msg: "服务器错误: #{e.message}", data: nil }, status: :internal_server_error
  end

  # 外部传入文件路径，截取文件名后校验在 grok-videos bucket 中是否存在，存在则返回 OSS 签名 URL
  def video_url
    path = params[:path].to_s.strip

    if path.blank?
      render json: { code: 400, msg: '缺少 path 参数', data: nil }
      return
    end

    # 从路径中截取文件名（兼容 URL / Linux 路径 / Windows 路径）
    filename = path.split('?').first.split(/[\/\\]/).last.to_s

    if filename.blank?
      render json: { code: 400, msg: '无法从路径中解析出文件名', data: nil }
      return
    end

    bucket_name = 'grok-videos'

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
end
