class ChangeExternalResourcesSourceToString < ActiveRecord::Migration[6.1]
  def up
    change_column :external_resources, :source, :string, null: false, default: 'grok_bot'
    execute "UPDATE external_resources SET source = 'grok_bot' WHERE source = '0'"
  end

  def down
    execute "UPDATE external_resources SET source = '0' WHERE source = 'grok_bot'"
    change_column :external_resources, :source, :integer, null: false, default: 0
  end
end
