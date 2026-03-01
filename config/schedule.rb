set :environment, :development
every :day, at: '00:05' do
  runner 'TaskScheduler.pending_task'
end