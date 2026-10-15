# ===== X 平台评论互动本地测试（不改动系统代码）=====
#
# 现有授权 scope（dm.read dm.write tweet.read tweet.write users.read offline.access media.write）
# 已覆盖「读回复 + 发回复」；「点赞」需要 like.write，当前授权未包含，like 命令预期返回 403（可实测验证）。
#
# 用法（项目根目录执行）：
#   列出已授权的 X 账号：
#     bundle exec rails runner scripts/test_x_comments.rb list
#   验证 token（users/me）：
#     bundle exec rails runner scripts/test_x_comments.rb me <account_id>
#   我的最近推文（拿 tweet_id 用）：
#     bundle exec rails runner scripts/test_x_comments.rb my_tweets <account_id> [条数，默认5]
#   查看单条推文：
#     bundle exec rails runner scripts/test_x_comments.rb tweet <account_id> <tweet_id>
#   读取推文下的回复（默认 search 端点；可指定 replies 新端点，可用性随套餐）：
#     bundle exec rails runner scripts/test_x_comments.rb replies <account_id> <tweet_id> [search|replies]
#   用当前账号回复某条推文/评论（公开发布，需输入 y 确认）：
#     bundle exec rails runner scripts/test_x_comments.rb reply <account_id> <tweet_id> 回复内容...
#   点赞实测（预期 403，验证 scope 是否需要重新授权）：
#     bundle exec rails runner scripts/test_x_comments.rb like <account_id> <tweet_id>

require 'net/http'
require 'uri'
require 'json'

API_BASE = 'https://api.twitter.com'

# ---- 本地小工具：X API v2 评论区端点（XApi 未封装，测试独立实现，不动系统代码）----

def x_get(token, path, params = {})
  uri = URI("#{API_BASE}#{path}")
  uri.query = URI.encode_www_form(params) if params.any?
  req = Net::HTTP::Get.new(uri)
  req['Authorization'] = "Bearer #{token}"
  req['Accept'] = 'application/json'
  x_perform(uri, req)
end

def x_post(token, path, body)
  uri = URI("#{API_BASE}#{path}")
  req = Net::HTTP::Post.new(uri)
  req['Authorization'] = "Bearer #{token}"
  req['Content-Type'] = 'application/json'
  req.body = body.to_json
  x_perform(uri, req)
end

def x_perform(uri, req)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.open_timeout = 30
  http.read_timeout = 60
  resp = http.request(req)
  raw = resp.body.to_s
  parsed = raw.present? ? JSON.parse(raw) : {}
  { code: resp.code.to_i, body: parsed, raw: raw }
rescue => e
  { code: 0, body: {}, raw: "网络异常: #{e.message}" }
end

def find_account!(id)
  account = Account.find_by(id: id.to_i)
  abort "账号 #{id} 不存在" unless account
  account
end

def token_for!(account)
  token = XAuthService.access_token_for(account)
  if token.blank?
    abort "✗ 拿不到有效 token（未认证或 token 刷新失败，auth_status=#{account.x_credential&.auth_status}）"
  end
  puts "✓ token: #{token[0, 8]}... (x_user_id=#{account.x_credential&.x_user_id})"
  token
end

def user_index(resp)
  (resp.dig(:body, 'includes', 'users') || []).index_by { |u| u['id'] }
end

def print_tweet(t, users_by_id)
  return unless t.is_a?(Hash)
  author = "@#{t['author_id']}"
  if (u = users_by_id[t['author_id']])
    author = "@#{u['username']} (#{u['name']})"
  end
  puts "  [#{t['id']}] #{author} at=#{t['created_at']} | #{t['text'].to_s.truncate(80)}"
end

def print_fail(tag, resp)
  puts "✗ #{tag}失败: code=#{resp[:code]} raw=#{resp[:raw].to_s.truncate(300)}"
end

TWEET_FIELDS = { 'tweet.fields' => 'created_at,author_id,conversation_id,in_reply_to_user_id',
                 expansions: 'author_id', 'user.fields' => 'username,name' }.freeze

# ---- 子命令 ----

cmd = ARGV[0] || 'list'

case cmd
when 'list'
  xcs = XCredential.where(auth_status: :authorized).includes(:account)
  abort '没有已授权的 X 账号（XCredential auth_status=authorized 为空）' if xcs.empty?
  puts "已授权 X 账号 #{xcs.size} 个："
  xcs.each do |xc|
    a = xc.account
    exp = xc.token_expires_at.present? ? xc.token_expires_at.strftime('%Y-%m-%d %H:%M') : '未知'
    puts "  account_id=#{a.id} #{a.account_name} x_user_id=#{xc.x_user_id} token过期=#{exp}（过期会自动刷新）"
  end
  puts "\nscope: #{xcs.first.scope}"

when 'me'
  account = find_account!(ARGV[1])
  token = token_for!(account)
  resp = XApi.me(access_token: token)
  if XApi.success?(resp) && (d = resp[:body]['data'])
    puts "✓ 当前用户: id=#{d['id']} @#{d['username']} name=#{d['name']}"
  else
    print_fail('me', resp)
  end

when 'my_tweets'
  account = find_account!(ARGV[1])
  count = [(ARGV[2] || 5).to_i, 100].min
  token = token_for!(account)
  x_user_id = account.x_credential&.x_user_id
  abort '✗ 凭证缺少 x_user_id（先跑 me 命令回填）' if x_user_id.blank?
  resp = x_get(token, "/2/users/#{x_user_id}/tweets", TWEET_FIELDS.merge(max_results: count))
  if XApi.success?(resp)
    tweets = resp[:body]['data'] || []
    puts "✓ 拉到 #{tweets.size} 条推文："
    tweets.each { |t| print_tweet(t, user_index(resp)) }
  else
    print_fail('拉取我的推文', resp)
  end

when 'tweet'
  account = find_account!(ARGV[1])
  tweet_id = ARGV[2].to_s
  abort '请提供 tweet_id' if tweet_id.blank?
  token = token_for!(account)
  resp = x_get(token, "/2/tweets/#{tweet_id}", TWEET_FIELDS)
  if XApi.success?(resp) && (t = resp[:body]['data'])
    print_tweet(t, user_index(resp))
  else
    print_fail('查看推文', resp)
  end

when 'replies'
  account = find_account!(ARGV[1])
  tweet_id = ARGV[2].to_s
  method = ARGV[3] || 'search'
  abort '请提供 tweet_id' if tweet_id.blank?
  token = token_for!(account)

  case method
  when 'search'
    # 方式 A（经典）：recent search 按 conversation_id 过滤，能拿到直接回复+嵌套回复，也受套餐读取额度限制
    puts "-- 方式 A: GET /2/tweets/search/recent?query=conversation_id:#{tweet_id}"
    resp = x_get(token, '/2/tweets/search/recent',
                 TWEET_FIELDS.merge(query: "conversation_id:#{tweet_id}", max_results: 100))
  when 'replies'
    # 方式 B（新端点）：GET /2/tweets/:id/replies，可用性随套餐，403 时回退方式 A 测
    puts "-- 方式 B: GET /2/tweets/#{tweet_id}/replies"
    resp = x_get(token, "/2/tweets/#{tweet_id}/replies", TWEET_FIELDS.merge(max_results: 100))
  else
    abort "未知方式 #{method}，可选 search / replies"
  end

  if XApi.success?(resp)
    tweets = resp[:body]['data'] || []
    users_by_id = user_index(resp)
    puts "✓ 拉到 #{tweets.size} 条回复"
    tweets.each { |t| print_tweet(t, users_by_id) }
    meta = resp[:body]['meta']
    puts "  meta: #{meta.inspect}" if meta
  else
    print_fail('拉取回复', resp)
    puts "  提示：403 多为套餐/权限限制，可换另一种方式（search ↔ replies）再试"
  end

when 'reply'
  account = find_account!(ARGV[1])
  tweet_id = ARGV[2].to_s
  text = ARGV[3..].to_a.join(' ')
  abort '请提供 tweet_id' if tweet_id.blank?
  abort '请提供回复内容' if text.blank?
  token = token_for!(account)

  # 先展示目标推文，确认回复对象
  target = x_get(token, "/2/tweets/#{tweet_id}", TWEET_FIELDS)
  if XApi.success?(target) && (t = target[:body]['data'])
    print_tweet(t, user_index(target))
  else
    puts "⚠ 查不到目标推文（code=#{target[:code]}），仍可继续尝试回复"
  end
  puts
  puts "将以「#{account.account_name}」的身份公开回复，内容："
  puts "  #{text}"
  print "确认发布？(y/n): "
  confirm = STDIN.gets.to_s.strip.downcase
  abort '已取消' unless confirm == 'y'

  resp = x_post(token, '/2/tweets', { text: text, reply: { in_reply_to_tweet_id: tweet_id } })
  if XApi.success?(resp)
    puts "✓ 回复成功: reply_tweet_id=#{resp.dig(:body, 'data', 'id')}"
  else
    print_fail('回复', resp)
  end

when 'like'
  account = find_account!(ARGV[1])
  tweet_id = ARGV[2].to_s
  abort '请提供 tweet_id' if tweet_id.blank?
  token = token_for!(account)
  x_user_id = account.x_credential&.x_user_id
  abort '✗ 凭证缺少 x_user_id（先跑 me 命令回填）' if x_user_id.blank?

  resp = x_post(token, "/2/users/#{x_user_id}/likes", { tweet_id: tweet_id })
  if XApi.success?(resp)
    puts "✓ 点赞成功（当前 scope 竟然能点赞，检查授权 scope）"
  else
    print_fail('点赞', resp)
    puts "  预期现象：当前授权 scope 不含 like.write → 403；后续要支持点赞需重新授权"
  end

else
  abort "未知命令 #{cmd}，可用：list / me / my_tweets / tweet / replies / reply / like"
end
