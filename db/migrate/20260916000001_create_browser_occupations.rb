class CreateBrowserOccupations < ActiveRecord::Migration[6.1]
  def change
    create_table :browser_occupations do |t|
      # 资源唯一标识：profile:<profile_name>（与机器端共通的指纹浏览器名）
      t.string   :resource_key, null: false, comment: "资源唯一标识（profile:<profile_name>）"
      t.string   :machine_ip,   null: false, comment: "所属运营机器 IP/域名"
      t.string   :profile_name, comment: "指纹浏览器名称（冗余，便于日志/排查）"
      t.string   :operation,    null: false, comment: "占用类型：publish/collect/nurture/kol/domestic"
      t.string   :task_ref,     comment: "任务引用（如 MoveTask#123，仅日志/排查用）"
      t.datetime :expires_at,   null: false, comment: "占用过期时间（崩溃兜底，正常走 release）"
      t.datetime :released_at,  comment: "释放时间；释放后保留 30s 作为冷却标记，之后被清理"

      t.timestamps
    end

    add_index :browser_occupations, :resource_key
    add_index :browser_occupations, :machine_ip
    add_index :browser_occupations, [:resource_key, :released_at]
    add_index :browser_occupations, :expires_at
  end
end
