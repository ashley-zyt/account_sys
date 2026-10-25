class RemoveMachineIpFromBrowsers < ActiveRecord::Migration[6.1]
  def change
    remove_column :browsers, :machine_ip, :string
  end
end
