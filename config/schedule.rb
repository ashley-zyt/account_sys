set :environment, :development

set :output, "log/pending_task.log"
every :day, at: '15:50' do
  runner 'TaskScheduler.pending_task'
end