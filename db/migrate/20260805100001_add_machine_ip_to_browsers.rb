class AddMachineIpToBrowsers < ActiveRecord::Migration[7.0]
  # 一个指纹浏览器(browser)固定由一台运营机器运营
  # machine_ip 存储该浏览器所属运营机器的 IP（端口按用途固定：养号 8080，cloud_id 同步 8384）
  def up
    add_column :browsers, :machine_ip, :string, comment: "运营机器IP（该浏览器固定由这台机器运营，避免频繁换IP导致封号）"

    # 回填：根据现有 warmup_profiles.machine 将 IP 迁移到 browser.machine_ip
    #   move  -> 174.139.46.117
    #   other -> 174.139.46.15
    # 优先按 move 归属；无 move 账号的浏览器按 other 归属
    execute <<~SQL
      UPDATE browsers
      SET machine_ip = CASE
        WHEN EXISTS (
          SELECT 1 FROM accounts
          INNER JOIN warmup_profiles ON warmup_profiles.account_id = accounts.id
          WHERE accounts.browser_id = browsers.id
            AND warmup_profiles.machine = 'move'
        ) THEN '174.139.46.117'
        ELSE '174.139.46.15'
      END
      WHERE EXISTS (
        SELECT 1 FROM accounts
        INNER JOIN warmup_profiles ON warmup_profiles.account_id = accounts.id
        WHERE accounts.browser_id = browsers.id
      )
    SQL

    add_index :browsers, :machine_ip
  end

  def down
    remove_index :browsers, :machine_ip if index_exists?(:browsers, :machine_ip)
    remove_column :browsers, :machine_ip
  end
end
