# 定时任务：把已完成但未推送到花生资源队列的 HuashengKeyword 推送过去。
#
# 触发：config/schedule.rb 中 every 1.hour 调用 HuashengQueueScheduler.run
# 逻辑：
#   1. 扫描所有 status=3（执行完成）且 pushed=false 的 HuashengKeyword
#   2. 调用 HuashengTask.create_from_huasheng_keyword! 生成 5 个平台的任务
#   3. 推送成功（created > 0）后将该 HuashengKeyword 标记为 pushed=true
class HuashengQueueScheduler
  # 一次最多处理多少条，避免单次跑得过久
  BATCH_LIMIT = 100

  def self.run
    logger = ActiveSupport::Logger.new(File.join(Rails.root, "log", "huasheng_queue_scheduler.log"))
    logger.formatter = Rails.logger.formatter
    Rails.logger = logger

    Rails.logger.info "[HuashengQueueScheduler] start at #{Time.now}"

    keywords = HuashengKeyword.where(status: 3, pushed: false).order(id: :asc).limit(BATCH_LIMIT)
    total = keywords.size
    Rails.logger.info "[HuashengQueueScheduler] 待推送 #{total} 条"

    success = 0
    skipped = 0
    failed = 0

    keywords.each do |kw|
      # 跳过包含 | 分隔符的多段式关键词（如 "宁夏灵武市|Chinese|9:16"），
      # 这类关键词由 voice_video_pipeline 独立处理，不推送到花生资源队列。
      if kw.keyword&.include?("|")
        # kw.update!(pushed: true)
        skipped += 1
        Rails.logger.info "[HuashengQueueScheduler] keyword #{kw.id} (#{kw.keyword}) 多段式关键词，跳过推送"
        next
      end

      begin
        created, err = HuashengTask.create_from_huasheng_keyword!(kw)

        if err.present? && created == 0
          # 幂等跳过（"已入库资源队列"）也算成功，标记 pushed=true 避免下次重复扫描
          if err.include?("已入库")
            kw.update!(pushed: true)
            skipped += 1
            Rails.logger.info "[HuashengQueueScheduler] keyword #{kw.id} 已存在，标记 pushed"
          else
            failed += 1
            Rails.logger.warn "[HuashengQueueScheduler] keyword #{kw.id} 推送失败: #{err}"
          end
        elsif created > 0
          kw.update!(pushed: true)
          success += 1
          Rails.logger.info "[HuashengQueueScheduler] keyword #{kw.id} 推送 #{created} 条任务成功"
        else
          # created == 0 且无错误信息，保守起见不标记，下次再试
          Rails.logger.warn "[HuashengQueueScheduler] keyword #{kw.id} 推送 0 条，未标记 pushed"
        end
      rescue => e
        failed += 1
        Rails.logger.error "[HuashengQueueScheduler] keyword #{kw.id} 异常: #{e.class} #{e.message}"
      end
    end

    Rails.logger.info "[HuashengQueueScheduler] done: 成功 #{success}，跳过 #{skipped}，失败 #{failed}，总计 #{total}"
  end
end
