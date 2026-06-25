class Util
  def self.tmp_fun
    theme = "大熊猫Baobao"
    title = "Not perfect. Still iconic. 🐼 #BaoBao #DanceTrend #Confidence #PandaTok #FunnyPanda #TrendingNow"
    description = "Not perfect. Still iconic. 🐼"
    oss_url = "http://operation-viodes.oss-cn-hangzhou.aliyuncs.com/d9693de2-09a9-4b18-beff-6d6e89e093fb_178237487.mp4?OSSAccessKeyId=LTAI5tFKwps3PgNdpi69ab7p&Expires=1813910997&Signature=rDYuhCTA9NT4nNaa0mCyk0rFMhM%3D"
    platforms = %w[facebook twitter tiktok instagram]
    group_id = SecureRandom.uuid
    platforms.each do |platform|
    OperationTask.create(
    theme: theme,
    title: title,
    oss_url: oss_url,
    platform: platform,
    status: :pending,
    group_id: group_id
    )
    end
    OperationTask.create(
    theme: theme,
    title: description,
    description: title,
    oss_url: oss_url,
    platform: "youtube",
    status: :pending,
    group_id: group_id
    )
  end
end