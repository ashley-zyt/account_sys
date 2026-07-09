class SetAccountMachineByWorkType < ActiveRecord::Migration[7.0]
  def up
    Account.where(work_type: "视频搬运").update_all(machine: 'move')
    Account.where.not(work_type: "视频搬运").update_all(machine: 'other')
  end

  def down
    Account.update_all(machine: 'move')
  end
end