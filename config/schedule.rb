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
  runner 'TaskScheduler.assign_operation_resources'
end
set :output, "log/taskscheduler_assigngrokresources.log"
every :day, at: '11:52' do
  runner 'TaskScheduler.assign_grok_resources'
end

# 每日12点开始自动发布人工运营和Grok的资源
set :output, "log/publishscheduler_run.log"
every :day, at: '12:00' do
  runner 'PublishScheduler.run'
end

# 分配资源 人工运营和Grok两种
# set :output, "log/taskscheduler_assignoperationresources.log"
# every :day, at: '16:50' do
#   runner 'TaskScheduler.assign_operation_resources'
# end
# set :output, "log/taskscheduler_assigngrokresources.log"
# every :day, at: '16:51' do
#   runner 'TaskScheduler.assign_grok_resources'
# end

# # 每日下午五点开始重试中午发布错误的人工运营和Grok资源
# set :output, "log/publishscheduler_run.log"
# every :day, at: '17:00' do
#   runner 'PublishScheduler.run'
# end


# set :output, "log/check_timeout_tasks.log"
# every 5.minutes do
#   runner 'TaskScheduler.check_timeout_tasks'
# end
