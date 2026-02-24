require 'selenium-webdriver'
require 'json'

URLS = ["https://www.douyin.com/user/MS4wLjABAAAAS2emYzTYdteuFsNKLDN-CQWOjz1YE3pD0AqdD0tdoxo?from_tab_name=main","https://www.douyin.com/user/MS4wLjABAAAAqJA8Ht-Og_K9OqEfZK3eH63B88x5KiP_ZdbGV5zd3Yw?from_tab_name=main","https://www.douyin.com/user/MS4wLjABAAAA32zID_nFiynF8R4rKuCM3xM1gMIQbD9IL-Ig0vxM6Zg","https://www.douyin.com/user/MS4wLjABAAAA2d1KA4bOkFmfB4zUvbcd6gQ0ljrneCoG47xZ7nRetgm0nO4dawRTvmH6FuiRhede","https://www.douyin.com/user/MS4wLjABAAAAubAaM1pAeOwEHlFrH0lXnCRJocfhdj2PgB8Y66GW5Co","https://www.douyin.com/user/MS4wLjABAAAAUn-Bc_6T7teQP8P6dCUJi3DG1S9IMRufsKdu4qopWEA","https://www.douyin.com/user/MS4wLjABAAAA2qfvNvzWJcaLJpZAxHt7ljdnMgbgg_2b1eU86B-iPg0","https://www.douyin.com/user/MS4wLjABAAAA1Ycxn9XWnm05hfs-16xqaLeMZBsk0msPS5cOq853g_k","https://www.douyin.com/user/MS4wLjABAAAAf66Bfj9I5Urd-m9LScDX08O6gpBGxN7kjbIDTvt6ARY","https://www.kuaishou.com/profile/3x7rqsbwmnm3fba","https://www.kuaishou.com/profile/3xt2ncahsaiajha","https://www.kuaishou.com/profile/3x693ddmu3qm6ii","https://www.kuaishou.com/profile/3xpsy7dsaxydezs","https://www.kuaishou.com/profile/3xiq77t2hj5gff6","https://space.bilibili.com/3493293230917643","https://space.bilibili.com/3493293358843909","https://space.bilibili.com/357071859","https://v.douyin.com/1zJy001KCRQ/","https://v.douyin.com/4GdkiV2IvtE/","https://v.douyin.com/YMDHT4Ck-kE/","https://v.douyin.com/tXTHoZx0zWA/","https://v.douyin.com/ncprJyxY-IE/","https://www.douyin.com/user/MS4wLjABAAAAYJodh6P_o7iy28LMJKJvXwsTtWx7dTMmqGAvmpllAjY","https://www.douyin.com/user/MS4wLjABAAAAGhPFeH61oaYrqK-XuNOexX9ES9w9GUwPqLdbp8roEtE?from_tab_name=main","https://www.douyin.com/user/MS4wLjABAAAAs9PSz5M175rsLuKRmsl3vMC4C-CMUyNiEDlz5N_o_jQ","https://www.douyin.com/user/MS4wLjABAAAAAw6hPn6OEwelBL6QxyZoSFjkuIkxDL0h6nfSYqv02xfij9ocC1aQHHftwSUT5pK9","https://www.douyin.com/user/MS4wLjABAAAAASxfKa9tZOloWB2PpLZsmUC92v3rn8CFZTUjQrAqpWOSX4iRo6uXN09mHgZ-nemo","https://www.kuaishou.com/profile/3xjhw9mskrka2cm","https://space.bilibili.com/1795428078","https://www.douyin.com/user/MS4wLjABAAAAqk6l_7oKl6pv-Ua5ALe-4JOQgZk9VZ35Tx0SCs3S1HBNtSeDLkwdSRD9Djv3GCYM?from_tab_name=main"]

def build_driver
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument('--headless=new')
  options.add_argument('--disable-gpu')
  options.add_argument('--no-sandbox')
  options.add_argument('--disable-dev-shm-usage')
  options.add_argument('--window-size=1920,1080')

  Selenium::WebDriver.for :chrome, options: options
end

def extract_links(html, platform)
  case platform
  when :douyin
    html.scan(/https:\/\/www\.douyin\.com\/video\/\d+/)
  when :kuaishou
    html.scan(/https:\/\/www\.kuaishou\.com\/short-video\/[a-zA-Z0-9]+/)
  when :bilibili
    html.scan(/https:\/\/www\.bilibili\.com\/video\/BV[0-9A-Za-z]+/)
  else
    []
  end.uniq
end

def detect_platform(url)
  return :douyin if url.include?("douyin.com")
  return :kuaishou if url.include?("kuaishou.com")
  return :bilibili if url.include?("bilibili.com")

  nil
end

driver = build_driver

URLS.each do |url|
  platform = detect_platform(url)
  next unless platform

  puts "\n==== 正在处理: #{url} ===="

  driver.navigate.to(url)
  sleep 8  # 等页面完全加载

  html = driver.page_source
  links = extract_links(html, platform)

  puts "共找到 #{links.count} 个视频链接"
  links.each { |l| puts l }
end

driver.quit