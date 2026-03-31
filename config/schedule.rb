set :environment, :development
set :output, "log/pending_task.log"
every :day, at: '20:00' do
  runner 'TaskScheduler.pending_task'
end