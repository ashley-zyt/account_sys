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
end
