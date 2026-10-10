# 给单个已认证 X 账号分配资源并发布（测试 X API 发布链路用）
#
# 用法：
#   bundle exec rails runner 'scripts/x_publish_one.rb'        # 自动选第一个已认证 X 账号
#   bundle exec rails runner 'scripts/x_publish_one.rb 123'    # 指定账号 ID

account_id = ARGV[0].to_i

account =
  if account_id > 0
    Account.find_by(id: account_id)
  else
    Account.joins(:x_credential)
           .where(platform: :twitter)
           .where(x_credentials: { auth_status: XCredential.auth_statuses[:authorized] })
           .order(:id).first
  end

abort '找不到账号（请确认存在已认证的 X 账号，或传入正确的账号 ID）' if account.nil?
abort "账号 ##{account.id} 不是 Twitter 平台" unless account.platform == 'twitter'

xc = account.x_credential
abort "账号 ##{account.id} 未完成 X 认证" unless xc&.authorized?

puts "目标账号：##{account.id} #{account.account_name} | platform=#{account.platform} work_type=#{account.work_type} theme=#{account.theme} x_user_id=#{xc.x_user_id}"

mode = WorkMode.scheduler_assign_modes.find { |m| m.name == account.work_type }
abort "找不到 work_type=#{account.work_type} 对应的任务模型" if mode.nil?
task_model = mode.task_model_class

task = task_model.where(status: :pending, platform: account.platform, theme: account.theme)
                 .order(:failure_count, created_at: :asc).first
abort "账号主题「#{account.theme}」暂无可用 pending 资源" if task.nil?

puts "找到待分配资源：#{task.class.name}##{task.id}"

ActiveRecord::Base.transaction do
  task.update!(account_id: account.id, browser_id: account.browser_id, status: :waiting_publish)
  TaskAssignment.record!(task)
end
puts "已分配：任务置为 waiting_publish，归属账号 ##{account.id}"

result = PublishScheduler.attempt_x_api_task(task)
task.reload
puts "提交结果：#{result.inspect} | 任务状态：#{task.status}"

if task.status == 'executing'
  xp = XPost.where(task_type: task.class.name, task_id: task.id).order(:id).last
  puts "已提交上传（media_id=#{xp&.media_id}），XPostPoller 约 1 分钟内发推并回写终态。可稍后查 x_posts 表 / log/x_post_poller.log"
elsif %w[pending failed].include?(task.status)
  puts "发布未成功，error_msg=#{task.error_msg}"
end
