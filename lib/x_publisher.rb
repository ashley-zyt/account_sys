# X（Twitter）API 发布执行器。
#
# 走 x_api 渠道的任务，这里完成「提交」阶段：下载 OSS 视频 → 分块上传 X（INIT/APPEND/FINALIZE）
# → 拿到 media_id → 记录 XPost(processing)。
# 后续的视频处理（STATUS 轮询）+ 发推由 XPostPoller 完成并回写任务 success/failed。
module XPublisher
  require 'open-uri'
  require 'tempfile'

  # X 建议单分块 ≤5MB，留余量取 ~4.5MB
  CHUNK_SIZE = 4_500_000

  # 提交发布（下载 + 上传 + FINALIZE），返回 { success:, message:, media_id: }
  def self.publish(task)
    account = task.account
    return { success: false, message: '账号未认证 X API，无法发布' } unless account&.x_credential&.authorized?

    token = XAuthService.access_token_for(account)
    return { success: false, message: '无法获取 X access_token（请重新认证）' } if token.blank?

    video_url = video_url_for(task)
    return { success: false, message: '任务无视频地址' } if video_url.blank?

    result = upload_video(token, video_url)
    return result unless result[:success]

    XPost.create!(task: task, media_id: result[:media_id], status: :processing)
    { success: true, message: "已提交 X 上传（media_id=#{result[:media_id]}）", media_id: result[:media_id] }
  end

  # 下载视频到临时文件 + INIT/APPEND/FINALIZE，返回 { success:, media_id: } 或 { success: false, message: }
  def self.upload_video(token, video_url)
    tmp = Tempfile.new(['x_upload', '.mp4'])
    begin
      download(video_url, tmp.path)
      total_bytes = File.size(tmp.path)

      init = XApi.media_upload_initialize(access_token: token, total_bytes: total_bytes)
      media_id = init[:body].is_a?(Hash) ? init[:body].dig('data', 'id').to_s : ''
      unless XApi.success?(init) && media_id.present?
        return { success: false, message: "X 初始化上传失败：#{init[:raw].to_s.truncate(200)}" }
      end

      # 分块 APPEND
      segment_index = 0
      File.open(tmp.path, 'rb') do |f|
        while (chunk = f.read(CHUNK_SIZE))
          append = XApi.media_upload_append(access_token: token, media_id: media_id, segment_index: segment_index, data: chunk)
          unless XApi.success?(append)
            return { success: false, message: "X 上传分块 #{segment_index} 失败：#{append[:raw].to_s.truncate(200)}" }
          end
          segment_index += 1
        end
      end

      fin = XApi.media_upload_finalize(access_token: token, media_id: media_id)
      unless XApi.success?(fin)
        return { success: false, message: "X 结束上传失败：#{fin[:raw].to_s.truncate(200)}" }
      end

      { success: true, media_id: media_id }
    rescue => e
      { success: false, message: "X 上传异常：#{e.message}" }
    ensure
      tmp.close!
    end
  end

  # 下载视频到本地文件（流式，避免大文件占内存）
  def self.download(url, dest_path)
    URI.open(url, 'rb') do |src|
      File.open(dest_path, 'wb') { |dst| IO.copy_stream(src, dst) }
    end
  end

  # 取任务视频地址（由 WorkMode 注册表决定 oss_url / video_url）
  def self.video_url_for(task)
    mode = WorkMode.for_model(task.class)
    return nil unless mode && mode.video_field.present?
    task.public_send(mode.video_field).to_s.presence
  end
end
