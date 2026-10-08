class AddFailureCountToResourceQueues < ActiveRecord::Migration[6.1]
  def change
    %w[
      move_tasks
      hunjian_tasks
      jianying_tasks
      operation_tasks
      grok_tasks
      heygen_tasks
      huasheng_tasks
      notebooklm_tasks
    ].each do |table|
      add_column table, :failure_count, :integer, default: 0, null: false,
                 comment: '发布失败次数，累计达到上限即判定资源不可用并删除'
    end
  end
end
