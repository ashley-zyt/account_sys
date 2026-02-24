class CreateBrowsers < ActiveRecord::Migration[6.1]
  def change
    create_table :browsers do |t|
      t.string  :profile_name, comment: '指纹浏览器名称'
      t.string  :cloud_id,     comment: '指纹浏览器名称ID'

      # 代理信息
      t.string  :proxy_type,     comment: '代理类型 http/socks5'
      t.string  :proxy_host,     comment: '代理IP'
      t.integer :proxy_port,     comment: '代理端口'
      t.string  :proxy_username, comment: '代理用户名'
      t.string  :proxy_password, comment: '代理密码'

      # 状态与用途（枚举）
      t.integer :status,  default: 0, comment: '浏览器状态：online/offline/network_error/busy'
      t.integer :purpose, default: 0, comment: '用途：养号/采集'

      t.string :remark, comment: '备注信息'

      t.timestamps
    end
  end
end
