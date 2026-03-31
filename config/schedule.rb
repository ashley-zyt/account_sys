set :environment, :development
every :day, at: '20:00' do
  runner 'TaskScheduler.pending_task'
end