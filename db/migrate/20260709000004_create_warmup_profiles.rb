class CreateWarmupProfiles < ActiveRecord::Migration[6.1]
  def change
    create_table :warmup_profiles do |t|
      t.references :account, null: false, foreign_key: true, unique: true
      t.datetime :last_warmup_at
      t.boolean :warmup_enabled, default: true
      t.string :warmup_frequency, default: 'weekly'
      t.string :warmup_status
      t.integer :warmup_batch, default: 0
      t.string :machine

      t.timestamps
    end

    add_index :warmup_profiles, :machine
    add_index :warmup_profiles, :warmup_batch
    add_index :warmup_profiles, :warmup_enabled
  end
end