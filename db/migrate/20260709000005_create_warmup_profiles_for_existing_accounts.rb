class CreateWarmupProfilesForExistingAccounts < ActiveRecord::Migration[6.1]
  def up
    Account.find_each do |account|
      next if account.warmup_profile.present?

      WarmupProfile.create!(
        account: account,
        machine: account.work_type == '视频搬运' ? 'move' : 'other'
      )
    end
  end

  def down
    WarmupProfile.delete_all
  end
end