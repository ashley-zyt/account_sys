class Admin::HuashengKeywordsController < Admin::BaseController
  before_action :set_themes, only: [:index, :new, :create, :edit, :update]

  def index
    @q = HuashengKeyword.ransack(params[:q])
    @huasheng_keywords = @q.result
                            .order(created_at: :desc)
                            .page(params[:page])
  end

  def new
    @huasheng_keyword = HuashengKeyword.new
    render :new, layout: false if request.xhr?
  end

  def create
    lines = params[:keywords_text].to_s.strip.lines.map(&:strip).reject(&:blank?)

    if lines.empty?
      render json: { success: false, error: "请输入至少一个关键词" }, status: :unprocessable_entity
      return
    end

    theme = params[:theme].to_s.strip
    if theme.blank?
      render json: { success: false, error: "请选择主题" }, status: :unprocessable_entity
      return
    end

    theme = theme.gsub("剪映-", "")

    created = []
    failed = []

    lines.each do |line|
      kw = HuashengKeyword.new(theme: theme, keyword: line)
      if kw.save
        created << kw
      else
        failed << { line: line, error: kw.errors.full_messages.join(", ") }
      end
    end

    if created.any?
      if failed.any?
        flash[:notice] = "成功添加 #{created.size} 个关键词"
        flash[:alert] = "#{failed.size} 个失败：#{failed.map { |f| f[:error] }.join('；')}"
      else
        flash[:notice] = "成功添加 #{created.size} 个关键词"
      end
    else
      flash[:alert] = "添加失败：#{failed.first&.dig(:error) || '未知错误'}"
    end

    redirect_to admin_huasheng_keywords_path
  rescue => e
    Rails.logger.error "[HuashengKeywords] 批量添加失败: #{e.message}"
    render json: { success: false, error: e.message }, status: :unprocessable_entity
  end

  # huasheng-ld bucket 与 voice_video_pipeline 上传时使用的 OSS 凭证一致。
  # 参考 scripts/update_jianying_tasks.rb#oss_v1_sign_url，生成 V1 GET 签名 URL。
  HUASHENG_OSS_BUCKET = "huasheng-ld".freeze
  HUASHENG_OSS_REGION = "cn-hangzhou".freeze
  HUASHENG_OSS_ACCESS_KEY_ID = "gZL8z938T19mSUHf".freeze
  HUASHENG_OSS_ACCESS_KEY_SECRET = "A9fSDa9cH5YAExpEUR4QSizkFQEcrS".freeze
  HUASHENG_OSS_SIGNED_URL_TTL = 31_536_000 # 1 年

  def show
    @huasheng_keyword = HuashengKeyword.find(params[:id])
    @video_url = build_huasheng_video_url(@huasheng_keyword.result_data)
    render layout: false if request.xhr?
  end

  def edit
    @huasheng_keyword = HuashengKeyword.find(params[:id])
    render layout: false if request.xhr?
  end

  def update
    @huasheng_keyword = HuashengKeyword.find(params[:id])
    if @huasheng_keyword.update(huasheng_keyword_params)
      redirect_to admin_huasheng_keywords_path, notice: "关键词更新成功"
    else
      @themes = Theme.pluck(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @huasheng_keyword = HuashengKeyword.find(params[:id])
    unless @huasheng_keyword.status == 0
      redirect_to admin_huasheng_keywords_path, alert: "仅未启动的任务可以删除"
      return
    end
    @huasheng_keyword.destroy
    redirect_to admin_huasheng_keywords_path, notice: "关键词删除成功"
  end

  private

  def set_themes
    @themes = Theme.pluck(:name)
  end

  def huasheng_keyword_params
    params.require(:huasheng_keyword).permit(:theme, :keyword)
  end

  # 解析 result_data JSON，从中取出 oss_url（实为 object key，如 "video/video_xxx.mp4"），
  # 返回 1 年有效的 OSS V1 GET 签名 URL。失败返回 nil。
  def build_huasheng_video_url(result_data)
    return nil if result_data.blank?
    result = JSON.parse(result_data) rescue {}
    object_key = result["oss_url"].to_s.strip.gsub(/^`|`$/, "").strip
    return nil if object_key.blank?
    huasheng_oss_v1_sign_url(object_key)
  end

  # OSS V1 GET 签名 URL（参考 scripts/update_jianying_tasks.rb#oss_v1_sign_url）
  def huasheng_oss_v1_sign_url(key)
    require "openssl"
    require "base64"

    key = key.sub(%r{^/}, "")
    expires = (Time.now.to_i + HUASHENG_OSS_SIGNED_URL_TTL).to_s
    string_to_sign = "GET\n\n\n#{expires}\n/#{HUASHENG_OSS_BUCKET}/#{key}"
    signature = Base64.strict_encode64(
      OpenSSL::HMAC.digest("sha1", HUASHENG_OSS_ACCESS_KEY_SECRET, string_to_sign)
    ).strip

    encoded_key = key.split("/").map { |seg| percent_encode_oss(seg) }.join("/")
    "https://#{HUASHENG_OSS_BUCKET}.oss-#{HUASHENG_OSS_REGION}.aliyuncs.com/#{encoded_key}?" \
      "OSSAccessKeyId=#{HUASHENG_OSS_ACCESS_KEY_ID}" \
      "&Expires=#{expires}" \
      "&Signature=#{percent_encode_oss(signature)}"
  end

  def percent_encode_oss(str)
    URI.encode_www_form_component(str.to_s).gsub("+", "%20")
  end
end
