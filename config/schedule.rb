# config/schedule.rb
every 5.minutes do
  runner "TaskScheduler.pending_task"
end