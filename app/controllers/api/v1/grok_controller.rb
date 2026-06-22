class Api::V1::GrokController < ApplicationController
  # 获取Grok图片资源列表
  def images
    grok_images = GrokImageResource.all

    data = grok_images.map do |img|
      theme = Theme.find_by(name: img.theme)
      prompts = theme&.prompts_array || []

      {
        id: img.id,
        image_url: img.image_url,
        prompts: prompts
      }
    end

    render json: {
      code: 200,
      msg: 'success',
      data: data
    }
  rescue => e
    render json: { code: 500, msg: "服务器错误: #{e.message}" }, status: :internal_server_error
  end
end
