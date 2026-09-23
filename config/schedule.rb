set :environment, :development

# set :output, "log/pending_task.log"
# every :day, at: '15:50' do
#   runner 'TaskScheduler.pending_task'
# end

# 每日凌晨 02:00 - 07:00 分批采集发文数据：每小时一轮，每台机器每轮取 30 个「今日未获取」的账号。
# 幂等：今天已采到数据的账号（post_stats 有更新 / account_stat 有今日快照）自动跳过；
# 每轮按 id 升序取前 30 个，采完变「已更新」下轮自然轮转到下一批，避免一次性堆积 + 中断自愈。
set :output, "log/postdatas_fetch.log"
every :day, at: ['01:00', '02:00', '03:00', '04:00', '05:00', '06:00', '07:00', '08:00'] do
  runner 'PostDatas.fetch_uncollected_by_machine'
end
# 做数字货币视频
# set :output, "log/heygen_crypto_video_pipeline.log"
# every :day, at: '07:10' do
#   runner 'Heygen.run_crypto_video_pipeline'
# end
# 获取数字货币视频生成结果
# set :output, "log/heygen_fetch_video_info.log"
# every :day, at: '07:40' do
#   runner 'Heygen.fetch_video_info'
# end

# ==================== 异步任务超时兜底 ====================
# 每 10 分钟检查一次：下发超时（45 分钟）仍无回调的异步任务，主动查机器端真实状态补结果或重置
set :output, "log/task_timeout_check.log"
every 10.minutes do
  runner 'TaskScheduler.check_timeout_tasks'
end

# ==================== Undetectable 暂停任务自动恢复 ====================
# 每 5 分钟检查各机器是否有「因 Undetectable 未启动而暂停」的任务：
#   有 → 调 POST /tasks/resume 自动恢复（熔断已清 + Undetectable 可用时，机器端会重放发布类任务）；
#   非发布类（养号/采集/私信）由本任务重新下发；超过 20 分钟仍未恢复 → 用 agic_zyt 发一次钉钉告警。
set :output, "log/machine_pause_monitor.log"
every 5.minutes do
  runner 'MachinePauseMonitor.run'
end


# ==================== 平台分批发布配置 ====================
# Instagram: 8:00 发布，7:50 分配资源
set :output, "log/taskscheduler_assignresources_instagram.log"
every :day, at: '08:55' do
  runner "TaskScheduler.assign_resources(platform: 'instagram')"
end

set :output, "log/publishscheduler_run_instagram.log"
every :day, at: '9:00' do
  runner "PublishScheduler.run(platform: 'instagram')"
end

# Twitter: 12:00 发布，11:50 分配资源
set :output, "log/taskscheduler_assignresources_twitter.log"
every :day, at: '11:50' do
  runner "TaskScheduler.assign_resources(platform: 'twitter')"
end

set :output, "log/publishscheduler_run_twitter.log"
every :day, at: '12:00' do
  runner "PublishScheduler.run(platform: 'twitter')"
end

# YouTube: 工作日14:00发布，周末9:00发布，发布前10分钟分配资源
set :output, "log/taskscheduler_assignresources_youtube.log"
every :weekday, at: '13:50' do
  runner "TaskScheduler.assign_resources(platform: 'youtube')"
end

set :output, "log/publishscheduler_run_youtube.log"
every :weekday, at: '14:00' do
  runner "PublishScheduler.run(platform: 'youtube')"
end

set :output, "log/taskscheduler_assignresources_youtube.log"
every [:saturday, :sunday], at: '8:50' do
  runner "TaskScheduler.assign_resources(platform: 'youtube')"
end

set :output, "log/publishscheduler_run_youtube.log"
every [:saturday, :sunday], at: '9:00' do
  runner "PublishScheduler.run(platform: 'youtube')"
end

# TikTok: 17:55 发布，17:50 分配资源
set :output, "log/taskscheduler_assignresources_tiktok.log"
every :day, at: '17:50' do
  runner "TaskScheduler.assign_resources(platform: 'tiktok')"
end

set :output, "log/publishscheduler_run_tiktok.log"
every :day, at: '17:55' do
  runner "PublishScheduler.run(platform: 'tiktok')"
end

# Facebook: 20:00 发布，19:50 分配资源
set :output, "log/taskscheduler_assignresources_facebook.log"
every :day, at: '19:50' do
  runner "TaskScheduler.assign_resources(platform: 'facebook')"
end

set :output, "log/publishscheduler_run_facebook.log"
every :day, at: '20:00' do
  runner "PublishScheduler.run(platform: 'facebook')"
end

# RedNote 关键词任务状态同步（每30分钟）
set :output, "log/red_note_sync.log"
every 30.minutes do
  runner 'RedNoteApiService.sync_all_pending'
end

# RedNote 随机创建任务（每3小时，从未启动中随机取1~4条）
set :output, "log/red_note_random_tasks.log"
every 3.hours do
  runner 'RedNoteApiService.random_create_tasks'
end


# ==================== 花生资源队列推送 ====================
# 每小时扫描已完成（status=3）且未推送的花生关键词，推送到花生资源队列
set :output, "log/huasheng_queue_scheduler.log"
every 1.hour do
  runner 'HuashengQueueScheduler.run'
end

# ==================== NotebookLM 资源队列推送 ====================
# 每小时扫描已完成（status=3）且未推送的 NotebookLM 关键词，推送到 NotebookLM 资源队列
set :output, "log/notebooklm_queue_scheduler.log"
every 1.hour do
  runner 'NotebooklmQueueScheduler.run'
end


# ==================== 养号任务配置 ====================
# 每晚 21:00 - 次日 01:00 每小时一轮，按 browser.machine_ip 分组，多台机器并行运行、互不影响。
# - 每轮每台机器最多下发 5 个账号（MAX_ACCOUNTS_PER_MACHINE），按顺序轮转、每轮不重复
# - 机器IP在浏览器页面动态管理，无需改代码
set :output, "log/warmup_scheduler.log"
every :day, at: ['20:00', '21:00', '22:00', '23:00', '00:00'] do
  runner 'WarmupScheduler.run'
end

# 养号卡死兜底：每小时回收「卡在 executing 超过 3 小时仍无回调」的养号任务（机器中断/重启/丢失），
# 标 failed 释放账号，下一轮重新养号。
set :output, "log/warmup_stuck_recovery.log"
every 1.hour do
  runner 'WarmupScheduler.recover_stuck_tasks'
end


# ==================== KOL 自动化触达与管理 ====================
# 每小时扫描待联系（Pending）队列，确认满足条件后依次调用 API 发送消息
set :output, "log/kol_scheduler.log"
every 1.hour do
  runner 'KolScheduler.run'
end

# 每 3 小时检查联系中（Contacting）的 KOL，确认对方是否回复
set :output, "log/kol_reply_poller.log"
every 3.hours do
  runner 'KolReplyPoller.run'
end


# ==================== 花生视频 抖音/视频号 自动发布 ====================
# 每天下午 16:00 获取一条「执行完成」的花生关键词，发布到抖音、视频号，结果钉钉通知
set :output, "log/domestic_huasheng_publish_worker.log"
every :day, at: '16:00' do
  runner 'DomesticHuashengPublishWorker.run'
end


# ==================== 发布状况日报 ====================
# 每天晚上 20:00 统计前一日（昨天）各平台正常状态账号数与发文数（对比前天，前天无快照则以昨日数值为基准），推送到钉钉「发布状况」群
set :output, "log/publish_status_report.log"
every :day, at: '14:30' do
  runner 'PublishStatusReport.run'
end


# ==================== 抖音/视频号 账号登录状态检查 ====================
# 每天凌晨 15:30 检查两个平台账号是否登录，未登录时通过钉钉提醒
set :output, "log/domestic_login_status.log"
every :day, at: '15:00' do
  runner 'DomesticLoginStatusChecker.run'
end

