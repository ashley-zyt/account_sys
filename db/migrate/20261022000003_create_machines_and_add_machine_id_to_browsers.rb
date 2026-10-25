class CreateMachinesAndAddMachineIdToBrowsers < ActiveRecord::Migration[6.1]
  # 旧 machine_ip 值 → 新机器（name=稳定标识, host=当前地址）
  # 换服务器时只改 machines.host，无需再动 browsers.machine_ip。
  MACHINE_MAP = {
    '机器A' => { host: 'agclienta.juzhiic.com', old_values: ['67.43.156.15', 'ag15.juzhiic.com'] },
    '机器B' => { host: 'agclientb.juzhiic.com', old_values: ['67.43.156.16', 'ag117.juzhiic.com'] }
  }.freeze

  def up
    create_table :machines do |t|
      t.string :name, null: false, comment: '机器稳定标识（如机器A/机器B）'
      t.string :host, null: false, comment: '当前地址（IP或域名），换服务器只改这里'
      t.string :remark, comment: '备注'
      t.timestamps
    end
    add_index :machines, :name, unique: true

    add_reference :browsers, :machine, foreign_key: true, index: true

    say_with_time '归并旧 machine_ip 到 machines' do
      MACHINE_MAP.each do |name, cfg|
        execute "INSERT INTO machines (name, host, created_at, updated_at) VALUES (#{quote(name)}, #{quote(cfg[:host])}, NOW(), NOW())"
        machine_id = select_value("SELECT id FROM machines WHERE name = #{quote(name)}")
        old_list = cfg[:old_values].map { |v| quote(v) }.join(', ')
        execute "UPDATE browsers SET machine_id = #{machine_id} WHERE machine_ip IN (#{old_list})"
      end
    end
  end

  def down
    remove_reference :browsers, :machine
    drop_table :machines
  end
end
