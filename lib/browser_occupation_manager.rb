# 浏览器占用中心 —— 统一管理「IP + 指纹浏览器」的并发互斥与每机器上限。
#
# 背景：系统中发文 / 采集 / 养号 / KOL / 抖音视频号 等操作都要「打开」指纹浏览器，
# 此前各调度器各自为政，跨任务类型没有互斥，容易出现在浏览器仍占用时又发下一个任务导致报错。
#
# 本中心提供：
#   - 同一浏览器同一时刻最多一个占用（互斥）
#   - 每台机器（machine_ip）最多 MAX_BROWSER_PER_IP 个活跃浏览器
#   - 释放后 COOLDOWN_SECONDS 冷却期（机器彻底关闭浏览器需要时间），冷却期内不可再次占用
#   - 崩溃兜底：ttl 过期自动清理
#
# 占用记录是「临时锁」：正常用完即 release（保留 30s 冷却后自动删除），不留长期历史。
#
# 用法（每个「开浏览器」的操作）：
#   occ = BrowserOccupationManager.acquire(BrowserOccupation.key_for_browser(browser),
#          machine_ip: ip, profile_name: browser.profile_name, operation: :publish,
#          task_ref: "MoveTask##{task.id}", ttl: 900)
#   begin
#     ... 发请求开浏览器 ...
#   ensure
#     BrowserOccupationManager.release(occ)
#   end
#
class BrowserOccupationManager
  # 每台机器最多同时活跃的浏览器数
  MAX_BROWSER_PER_IP = 4
  # 释放后的冷却时长（秒）：机器需要时间彻底关闭浏览器
  COOLDOWN_SECONDS = 30
  # 占用失败时的轮询间隔（秒）
  POLL_INTERVAL = 10
  # MySQL 命名锁：串行化 acquire/release 的登记动作（跨进程互斥；仅锁登记，不锁浏览器使用）
  LOCK_NAME = "account_sys_browser_occupation".freeze

  class << self
    # 申请占用。wait=true 时阻塞重试直到成功（占用失败/机器满都等待），返回 nil 表示放弃等待。
    # @return [BrowserOccupation, nil]
    def acquire(resource_key, machine_ip:, profile_name:, operation:, task_ref: nil, ttl: 600, wait: true)
      loop do
        result = try_acquire(resource_key, machine_ip: machine_ip, profile_name: profile_name,
                              operation: operation, task_ref: task_ref, ttl: ttl)
        return result[:occupation] if result[:status] == :ok
        return nil unless wait

        Rails.logger.info "[BrowserOccupation] #{resource_key} 占用失败（#{result[:status]}：#{result[:message]}），#{POLL_INTERVAL}s 后重试"
        sleep(POLL_INTERVAL)
      end
    end

    # 尝试占用一次（非阻塞）。返回 { status: :ok/:busy/:ip_full, occupation:, message: }
    def try_acquire(resource_key, machine_ip:, profile_name:, operation:, task_ref:, ttl:)
      with_lock do
        release_expired!

        return { status: :busy, occupation: nil, message: "该浏览器正在被占用或处于释放冷却期" } if occupied?(resource_key)

        if active_count(machine_ip) >= MAX_BROWSER_PER_IP
          return { status: :ip_full, occupation: nil, message: "机器 #{machine_ip} 活跃浏览器已达上限 #{MAX_BROWSER_PER_IP}" }
        end

        occupation = BrowserOccupation.create!(
          resource_key: resource_key,
          machine_ip: machine_ip,
          profile_name: profile_name,
          operation: operation.to_s,
          task_ref: task_ref,
          expires_at: Time.current + ttl.seconds,
          released_at: nil
        )
        { status: :ok, occupation: occupation, message: "占用成功" }
      end
    end

    # 释放占用：写 released_at 并保留 COOLDOWN_SECONDS 作为冷却标记
    # @return [BrowserOccupation, nil]
    def release(occupation_or_id)
      occupation = occupation_or_id.is_a?(BrowserOccupation) ? occupation_or_id : BrowserOccupation.find_by(id: occupation_or_id)
      return nil unless occupation

      with_lock do
        occupation.update!(released_at: Time.current, expires_at: Time.current + COOLDOWN_SECONDS.seconds)
      end
      occupation
    end

    # 按资源标识精确释放其当前活跃占用（供采集端/运营机器回传「已完成」时调用）
    # @param resource_key [String] 如 "profile:<profile_name>"
    # @return [BrowserOccupation, nil] 释放的占用；无活跃占用返回 nil
    def release_by_resource_key(resource_key)
      return nil if resource_key.blank?

      occupation = BrowserOccupation.where(resource_key: resource_key, released_at: nil)
                                    .where("expires_at > ?", Time.current)
                                    .order(created_at: :desc)
                                    .first
      release(occupation)
    end

    # 指定资源是否被占用（未过期活跃占用，或释放冷却期内）
    def occupied?(resource_key)
      BrowserOccupation.where(resource_key: resource_key, released_at: nil)
                       .where("expires_at > ?", Time.current)
                       .exists? ||
        BrowserOccupation.where(resource_key: resource_key)
                        .where("released_at IS NOT NULL AND released_at > ?", COOLDOWN_SECONDS.seconds.ago)
                        .exists?
    end

    # 某机器当前「未过期且未释放」的活跃占用数
    def active_count(machine_ip)
      BrowserOccupation.where(machine_ip: machine_ip, released_at: nil)
                       .where("expires_at > ?", Time.current)
                       .count
    end

    # 清理：ttl 过期且未释放（崩溃兜底）直接删；冷却标记超时删除
    def release_expired!
      BrowserOccupation.where("expires_at < ?", Time.current).delete_all
      BrowserOccupation.where("released_at IS NOT NULL AND released_at <= ?", COOLDOWN_SECONDS.seconds.ago).delete_all
    end

    # MySQL 命名锁：串行化登记动作。锁只覆盖「查询+插入/更新」这一瞬，不阻塞浏览器实际使用。
    # 检查 GET_LOCK 返回值（1=成功，0=超时未获得），失败则短暂重试，避免并发下漏锁。
    def with_lock
      conn = ActiveRecord::Base.connection
      acquired = false
      3.times do
        if conn.select_value("SELECT GET_LOCK('#{LOCK_NAME}', 10)").to_i == 1
          acquired = true
          break
        end
        sleep(0.2)
      end
      Rails.logger.error "[BrowserOccupation] 获取命名锁失败，本次登记未做串行化保护" unless acquired
      yield
    ensure
      conn&.select_value("SELECT RELEASE_LOCK('#{LOCK_NAME}')")
    end
  end
end
