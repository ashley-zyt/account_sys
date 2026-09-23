# 把 move_video 的「单流程状态」拆成「下载状态 + 剪映状态 + 混剪状态」三块。
#
# 背景：原 status 一个字段同时承载「下载」与「剪映」两个流程的状态，无法支持
# 「一个源视频既用于剪映、又用于混剪」的并行双流程。故拆分为：
#   - status          下载状态：pending_download / downloading / downloaded / failed
#   - jianying_status 剪映状态：pending / processing / completed / failed
#   - hunjian_status  混剪状态：pending / processing / completed / failed
#
# 旧 status 值映射（0=pending_download, 1=downloading, 2=pending_process,
# 3=processing, 4=processed, 5=failed）：
#   0 → status 0, jianying 0, hunjian 0
#   1 → status 1, jianying 0, hunjian 0
#   2 → status 2, jianying 0, hunjian 0   （pending_process 即「下载完成待剪映」）
#   3 → status 2, jianying 1, hunjian 0   （processing → 下载完成 + 剪映中）
#   4 → status 2, jianying 2, hunjian 0   （processed  → 下载完成 + 剪映完成）
#   5 → 按 error_msg 区分：
#         含「下载失败」→ status 3, jianying 0（下载失败）
#         其余          → status 2, jianying 3（剪映失败）
class SplitMoveVideoStatuses < ActiveRecord::Migration[6.1]
  def up
    add_column :move_videos, :jianying_status, :integer, default: 0, null: false, comment: '剪映流程状态 待剪映/剪映中/已完成/失败'
    add_column :move_videos, :hunjian_status,  :integer, default: 0, null: false, comment: '混剪流程状态 待混剪/混剪中/已完成/失败'

    # 数据迁移：按旧 status 值分步改写（每步 WHERE 基于尚未被前面步骤改变的值，顺序安全）
    # 1. pending_process(2)：下载完成、待剪映、待混剪
    execute "UPDATE move_videos SET jianying_status = 0, hunjian_status = 0 WHERE status = 2"
    # 2. processing(3)：下载完成、剪映中、待混剪
    execute "UPDATE move_videos SET status = 2, jianying_status = 1, hunjian_status = 0 WHERE status = 3"
    # 3. processed(4)：下载完成、剪映完成、待混剪
    execute "UPDATE move_videos SET status = 2, jianying_status = 2, hunjian_status = 0 WHERE status = 4"
    # 4. pending_download(0) / downloading(1)：待下载/下载中，两个流程均待
    execute "UPDATE move_videos SET jianying_status = 0, hunjian_status = 0 WHERE status IN (0, 1)"
    # 5. failed(5) 且下载失败：下载失败
    execute "UPDATE move_videos SET status = 3, jianying_status = 0, hunjian_status = 0 WHERE status = 5 AND error_msg LIKE '%下载失败%'"
    # 6. failed(5) 其余（剪映失败）：下载完成、剪映失败
    execute "UPDATE move_videos SET status = 2, jianying_status = 3, hunjian_status = 0 WHERE status = 5"

    add_index :move_videos, :jianying_status
    add_index :move_videos, :hunjian_status
  end

  def down
    remove_index :move_videos, :jianying_status
    remove_index :move_videos, :hunjian_status

    # 反向迁移：新三字段 → 旧 status
    #   status 3（下载失败）→ 5, jianying 3 → 5, jianying 1 → 3, jianying 2 → 4
    execute "UPDATE move_videos SET status = 5 WHERE status = 3"
    execute "UPDATE move_videos SET status = 5 WHERE jianying_status = 3"
    execute "UPDATE move_videos SET status = 3 WHERE jianying_status = 1"
    execute "UPDATE move_videos SET status = 4 WHERE jianying_status = 2"
    execute "UPDATE move_videos SET status = 2 WHERE status = 2"

    remove_column :move_videos, :jianying_status
    remove_column :move_videos, :hunjian_status
  end
end
