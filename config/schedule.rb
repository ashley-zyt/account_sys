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
every :day, at: '11:10' do
  runner 'Heygen.run_crypto_video_pipeline'
end
# 获取数字货币视频生成结果
set :output, "log/heygen_fetch_video_info.log"
every :day, at: '11:30' do
  runner 'Heygen.fetch_video_info'
end

# 分配资源（人工运营、Grok、Heygen）
set :output, "log/taskscheduler_assignresources.log"
every :day, at: '11:50' do
  runner 'TaskScheduler.assign_resources'
end

# 每日12点开始自动发布
set :output, "log/publishscheduler_run.log"
every :day, at: '12:00' do
  runner 'PublishScheduler.run'
end

# 下午重试前分配资源
set :output, "log/taskscheduler_assignresources.log"
every :day, at: '16:50' do
  runner 'TaskScheduler.assign_resources'
end

# 每日下午五点开始重试中午发布错误的人工运营和Grok资源
set :output, "log/publishscheduler_run.log"
every :day, at: '17:00' do
  runner 'PublishScheduler.run'
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

# # 加密货币视频生成流程（每天上午10点）
# set :output, "log/crypto_video_pipeline.log"
# every :day, at: '10:00' do
#   runner 'Heygen.run_crypto_video_pipeline'
# end

# # 检查Heygen视频生成状态（每10分钟）
# set :output, "log/heygen_video_status.log"
# every 10.minutes do
#   runner 'Heygen.process_pending_videos'
# end


# set :output, "log/check_timeout_tasks.log"
# every 5.minutes do
#   runner 'TaskScheduler.check_timeout_tasks'
# end
