# config/schedule.rb
every :day, at: '00:05' do
  runner 'TaskScheduler.pending_task'
end