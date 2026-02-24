class AddIndexesToAllTables < ActiveRecord::Migration[5.2]
  def change
    add_index :accounts, [:theme, :status, :last_used_at], name: 'idx_accounts_theme_status_lastused'
    add_index :move_tasks, [:status, :created_at], name: 'idx_tasks_status_created'
    add_index :move_tasks, [:theme, :status], name: 'idx_tasks_theme_status'
    add_index :task_logs, :run_at
  end
end