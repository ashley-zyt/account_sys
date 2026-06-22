set :environment, :development

set :output, "log/pending_task.log"
# every :day, at: '15:50' do
#   runner 'TaskScheduler.pending_task'
# end

every :day, at: '11:50' do
  runner 'TaskScheduler.assign_operation_resources'
end

every :day, at: '16:50' do
  runner 'TaskScheduler.assign_operation_resources'
end
