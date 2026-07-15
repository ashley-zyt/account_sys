class CreateWarmupTasks < ActiveRecord::Migration[6.1]
  def change
    create_table :warmup_tasks do |t|
      t.references :account, null: false, foreign_key: true
      t.references :browser, null: true, foreign_key: true
      t.integer :platform, null: false
      t.text :operations
      t.integer :status, default: 0
      t.text :error_msg
      t.datetime :executed_at
      t.string :task_uuid, unique: true
      t.integer :duration_minutes
      t.string :machine

      t.timestamps
    end

    add_index :warmup_tasks, :task_uuid
    add_index :warmup_tasks, [:account_id, :status]
    add_index :warmup_tasks, :platform
    add_index :warmup_tasks, :machine
    add_index :warmup_tasks, :executed_at
  end
end