class BackfillTaskLogsSnapshot < ActiveRecord::Migration[6.1]
	# 用历史任务中仍存在的 account_id / browser_id 回填快照字段
	# 注意：运营任务在失败后 account_id 会被置空，因此这部分历史日志无法回填
	def up
		# 搬运任务
		execute <<~SQL.squish
			UPDATE task_logs t
			JOIN move_tasks m ON m.task_uuid = t.task_uuid
			SET t.account_id = m.account_id,
			    t.browser_id = m.browser_id
			WHERE t.account_id IS NULL
		SQL

		# 剪映任务
		execute <<~SQL.squish
			UPDATE task_logs t
			JOIN jianying_tasks j ON j.task_uuid = t.task_uuid
			SET t.account_id = j.account_id,
			    t.browser_id = j.browser_id
			WHERE t.account_id IS NULL
		SQL

		# 运营任务（仅 account_id 尚未被清空的历史记录能回填）
		execute <<~SQL.squish
			UPDATE task_logs t
			JOIN operation_tasks o ON o.task_uuid = t.task_uuid
			SET t.account_id = o.account_id,
			    t.browser_id = o.browser_id
			WHERE t.account_id IS NULL AND o.account_id IS NOT NULL
		SQL
	end

	def down
		# 回填不可逆，no-op
	end
end
