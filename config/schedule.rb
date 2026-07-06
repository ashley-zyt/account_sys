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
# 分配资源 人工运营和Grok两种
set :output, "log/taskscheduler_assignoperationresources.log"
every :day, at: '11:50' do
  runner 'TaskScheduler.assign_resources'
end

# 每日12点开始自动发布人工运营和Grok的资源
set :output, "log/publishscheduler_run.log"
every :day, at: '12:00' do
  runner 'PublishScheduler.run'
end

# 分配资源 人工运营和Grok两种
set :output, "log/taskscheduler_assignoperationresources.log"
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


# set :output, "log/check_timeout_tasks.log"
# every 5.minutes do
#   runner 'TaskScheduler.check_timeout_tasks'
# end
