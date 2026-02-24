class Load
	def self.get_browsers
		arries = ["meishizhizuo1","meishizhizuo","banyun_tw_003","banyun_tw_003","banyun_tw_006","banyun_tw_003","hanfuxiu","zhongguowu","wushiwulong","wushiwulong","banyun_tw_004","wushiwulong","mingshengguji"]
		url = "http://174.139.46.15:8384/undetectable/list"
		res = RestClient.get(url) rescue nil
		if !res.nil?
			res = JSON.parse(res)
			datas = res["data"]
			datas.each do |data|
				puts profile_id = data[0]
				browser = data[1]
				working_types = 4
				puts adspower_user_name = browser["name"]
				account_type = 0
				if arries.include?adspower_user_name.to_s
					puts status = browser["status"]
					puts cloud_id = browser["cloud_id"]
					detail_url = "http://174.139.46.15:8384/undetectable/profile_id?profile_id=#{profile_id}"
					detail_res = RestClient.get(detail_url) rescue nil
					detail_res = JSON.parse(detail_res)
					proxy = detail_res["data"]["proxy"]
					without_protocol = proxy.sub(/^\w+:\/\//, '')
					parts = without_protocol.split(':')
					proxy_type = proxy_string.match(/^(\w+):/)[1] rescue ""
					proxy_host = parts[0] rescue ""
				    proxy_port = parts[1]  rescue ""
				    proxy_username = parts[2] rescue ""
				    proxy_password = parts[3] rescue ""
					Browser.create(profile_name: adspower_user_name, cloud_id: cloud_id, proxy_type: "socks5", proxy_host: proxy_host,proxy_port: proxy_port, proxy_username: proxy_username, proxy_password: proxy_password, status: "正常", purpose: "账号培育")
				end
			end
		end
	end
	def self.init_accounts
		records = [
			  { theme: "中国美食制作", platform_label: "YouTube", account_name: "52chinese_cuisine", browser_name: "meishizhizuo" },
			  { theme: "中国美食制作", platform_label: "Tik Tok", account_name: "52chinese_cuisine", browser_name: "meishizhizuo" },
			  { theme: "中国美食制作", platform_label: "脸书",   account_name: "52chinese_cuisine", browser_name: "meishizhizuo" },
			  { theme: "中国美食制作", platform_label: "推特",   account_name: "52chinese_cuisine", browser_name: "meishizhizuo" },

			  { theme: "武术表演",     platform_label: "YouTube", account_name: "Martial Arts Performance", browser_name: "banyun_tw_003" },
			  { theme: "武术表演",     platform_label: "Tik Tok", account_name: "wushuperformances",        browser_name: "banyun_tw_003" },
			  { theme: "武术表演",     platform_label: "脸书",     account_name: "wushuperformances",        browser_name: "banyun_tw_006" },
			  { theme: "武术表演",     platform_label: "推特",     account_name: "wushuperformances",        browser_name: "banyun_tw_003" },

			  { theme: "汉服秀",       platform_label: "YouTube", account_name: "Hanfu_lovers",             browser_name: "hanfuxiu" },
			  { theme: "汉服秀",       platform_label: "Tik Tok", account_name: "Hanfu_lovers",             browser_name: "hanfuxiu" },
			  { theme: "汉服秀",       platform_label: "脸书",     account_name: "Hanfu_lovers",             browser_name: "hanfuxiu" },
			  { theme: "汉服秀",       platform_label: "推特",     account_name: "Hanfu_lovers",             browser_name: "hanfuxiu" },

			  { theme: "中国舞",       platform_label: "YouTube", account_name: "Chinese_dance52",          browser_name: "zhongguowu" },
			  { theme: "中国舞",       platform_label: "Tik Tok", account_name: "Chinese_dance52",          browser_name: "zhongguowu" },
			  { theme: "中国舞",       platform_label: "脸书",     account_name: "Chinese_dance52",          browser_name: "zhongguowu" },
			  { theme: "中国舞",       platform_label: "推特",     account_name: "Chinese_dance52",          browser_name: "zhongguowu" },

			  { theme: "舞狮舞龙",     platform_label: "YouTube", account_name: "Loong Lion Show",          browser_name: "wushiwulong" },
			  { theme: "舞狮舞龙",     platform_label: "Tik Tok", account_name: "wushiwulong",              browser_name: "wushiwulong" },
			  { theme: "舞狮舞龙",     platform_label: "脸书",     account_name: "wushiwulong",              browser_name: "banyun_tw_004" },
			  { theme: "舞狮舞龙",     platform_label: "推特",     account_name: "wushiwulong",              browser_name: "wushiwulong" },

			  { theme: "名胜古迹",     platform_label: "YouTube", account_name: "WondersLog",               browser_name: "mingshengguji" },
			  { theme: "名胜古迹",     platform_label: "Tik Tok", account_name: "WondersLog",               browser_name: "mingshengguji" },
			  { theme: "名胜古迹",     platform_label: "脸书",     account_name: "WondersLog",               browser_name: "mingshengguji" },
			  { theme: "名胜古迹",     platform_label: "推特",     account_name: "WondersLog",               browser_name: "mingshengguji" }
			]

		platform_map = {
		  "YouTube" => :youtube,
		  "Tik Tok" => :tiktok,
		  "脸书"     => :facebook,
		  "推特"     => :twitter
		}

		records.each do |row|
		  theme         = row[:theme]
		  platform_sym  = platform_map[row[:platform_label]]
		  account_name  = row[:account_name]
		  browser_name  = row[:browser_name]

		  if platform_sym.nil?
		    puts "跳过：未知平台 #{row[:platform_label]} (#{account_name})"
		    next
		  end

		  browser = Browser.find_or_create_by!(profile_name: browser_name)

		  account = Account.find_or_initialize_by(
		    account_name: account_name,
		    platform: Account.platforms[platform_sym]
		  )

		  account.theme      = theme
		  account.status     = "正常"
		  account.work_type  = "视频搬运"
		  account.browser    = browser
		  account.remark   ||= ""

		  account.save!

		  puts "导入/更新账号：#{theme} - #{row[:platform_label]} - #{account_name}  绑定浏览器=#{browser.profile_name}"
		end
	end
end