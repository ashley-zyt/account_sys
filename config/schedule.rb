set :environment, :development

# set :output, "log/pending_task.log"
# every :day, at: '15:50' do
#   runner 'TaskScheduler.pending_task'
# end

# 每日推送浏览器账号数据到Windows机器采集发文数据
set :output, "log/postdatas_fetch.log"
every :day, at: '03:00' do
  runner 'PostDatas.fetch'
end
# 做数字货币视频
set :output, "log/heygen_crypto_video_pipeline.log"
every :day, at: '07:10' do
  runner 'Heygen.run_crypto_video_pipeline'
end
# 获取数字货币视频生成结果
set :output, "log/heygen_fetch_video_info.log"
every :day, at: '07:40' do
  runner 'Heygen.fetch_video_info'
end

# ==================== 平台分批发布配置 ====================
# Instagram: 8:00 发布，7:50 分配资源
set :output, "log/taskscheduler_assignresources_instagram.log"
every :day, at: '7:50' do
  runner "TaskScheduler.assign_resources(platform: 'instagram')"
end

set :output, "log/publishscheduler_run_instagram.log"
every :day, at: '8:00' do
  runner "PublishScheduler.run(platform: 'instagram')"
end

# Twitter: 12:00 发布，11:50 分配资源
set :output, "log/taskscheduler_assignresources_twitter.log"
every :day, at: '11:50' do
  runner "TaskScheduler.assign_resources(platform: 'twitter')"
end

set :output, "log/publishscheduler_run_twitter.log"
every :day, at: '12:00' do
  runner "PublishScheduler.run(platform: 'twitter')"
end

# YouTube: 工作日14:00发布，周末9:00发布，发布前10分钟分配资源
set :output, "log/taskscheduler_assignresources_youtube.log"
every :weekday, at: '13:50' do
  runner "TaskScheduler.assign_resources(platform: 'youtube')"
end

set :output, "log/publishscheduler_run_youtube.log"
every :weekday, at: '14:00' do
  runner "PublishScheduler.run(platform: 'youtube')"
end

set :output, "log/taskscheduler_assignresources_youtube.log"
every [:saturday, :sunday], at: '8:50' do
  runner "TaskScheduler.assign_resources(platform: 'youtube')"
end

set :output, "log/publishscheduler_run_youtube.log"
every [:saturday, :sunday], at: '9:00' do
  runner "PublishScheduler.run(platform: 'youtube')"
end

# TikTok: 19:00 发布，18:50 分配资源
set :output, "log/taskscheduler_assignresources_tiktok.log"
every :day, at: '18:50' do
  runner "TaskScheduler.assign_resources(platform: 'tiktok')"
end

set :output, "log/publishscheduler_run_tiktok.log"
every :day, at: '19:00' do
  runner "PublishScheduler.run(platform: 'tiktok')"
end

# Facebook: 20:00 发布，19:50 分配资源
set :output, "log/taskscheduler_assignresources_facebook.log"
every :day, at: '19:50' do
  runner "TaskScheduler.assign_resources(platform: 'facebook')"
end

set :output, "log/publishscheduler_run_facebook.log"
every :day, at: '20:00' do
  runner "PublishScheduler.run(platform: 'facebook')"
end

# RedNote 关键词任务状态同步（每30分钟）
set :output, "log/red_note_sync.log"
every 30.minutes do
  runner 'RedNoteApiService.sync_all_pending'
end

# RedNote 随机创建任务（每3小时，从未启动中随机取1~4条）
set :output, "log/red_note_random_tasks.log"
every 3.hours do
  runner 'RedNoteApiService.random_create_tasks'
end


# ==================== 养号任务配置 ====================
# 约束条件：
# - 每个账号养号：10-15分钟
# - 可用时间窗口：凌晨23:00-02:30（3小时）
# - 每批次可处理：约15个账号
# - 机器隔离：视频搬运在一台，其他模式在另一台
# - 策略：每天处理一批，轮流循环所有账号
# - 机器自动检测：通过环境变量 WARMUP_MACHINE 或主机名自动识别

# set :output, "log/warmup_scheduler.log"
# every :day, at: '23:00' do
#   runner 'WarmupScheduler.run'
# end

