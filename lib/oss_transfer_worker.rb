# 一次性批量预转存历史存量：把库里「oss_url 还是源 bucket」的任务逐个转存到主账号新 bucket。
#
# 场景：后续入库的任务会直接指向新 bucket，本任务只负责处理历史库里已存在的旧数据。
#       手动触发，一次性跑完（循环直到没有剩余旧数据，或本轮无任何成功——剩下的都是源对象已删等转存不了的）。
#
# 用法：bundle exec rails runner 'OssTransferWorker.run'
class OssTransferWorker
  # 每个模型每轮处理多少条（循环直到清空，避免单轮过久）
  PER_MODEL = 50

  def self.run
    logger = ActiveSupport::Logger.new(File.join(Rails.root, 'log', 'oss_transfer_worker.log'))
    logger.formatter = Rails.logger.formatter
    Rails.logger = logger

    Rails.logger.info "[OssTransferWorker] start at #{Time.now}"

    total_success = 0
    total_failed  = 0
    rounds = 0

    loop do
      result = OssTransfer.batch_transfer(per_model: PER_MODEL)
      rounds += 1
      total_success += result[:success]
      total_failed  += result[:failed]
      Rails.logger.info "[OssTransferWorker] 第 #{rounds} 轮: #{result.inspect}"

      # 没有剩余旧数据，或本轮一个都没成功（剩下的都是源对象已删等转存不了的），停止
      break if result[:total].zero? || result[:success].zero?
    end

    Rails.logger.info "[OssTransferWorker] 完成：共 #{rounds} 轮，成功 #{total_success}，失败 #{total_failed}"
    { success: total_success, failed: total_failed, rounds: rounds }
  rescue => e
    Rails.logger.error "[OssTransferWorker] 异常: #{e.class} #{e.message}"
    nil
  end
end
