class AddAccountAndBrowserSnapshotToTaskLogs < ActiveRecord::Migration[6.1]
	def change
		add_column :task_logs, :account_id, :bigint, comment: '执行账号ID快照（任务释放后仍保留关联）'
		add_column :task_logs, :browser_id, :string, comment: '执行浏览器ID快照（任务释放后仍保留关联）'
		add_index :task_logs, :account_id
		add_index :task_logs, :browser_id
	end
end
