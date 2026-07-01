set :environment, :development

set :output, "log/pending_task.log"
# every :day, at: '15:50' do
#   runner 'TaskScheduler.pending_task'
# end

# 每日推送浏览器账号数据到Windows机器采集发文数据
every :day, at: '03:00' do
  runner 'PostDatas.fetch'
end

every :day, at: '11:50' do
  runner 'TaskScheduler.assign_operation_resources'
end

every :day, at: '11:51' do
  runner 'TaskScheduler.assign_grok_resources'
end

every :day, at: '16:50' do
  runner 'TaskScheduler.assign_operation_resources'
end

every :day, at: '16:51' do
  runner 'TaskScheduler.assign_grok_resources'
end
