# -*- coding: utf-8 -*-
"""
X 平台评论互动外部测试脚本（脱离 account_sys 运行，只依赖 requests）

token 获取方式（二选一）：
  A. 从服务器自动拉（推荐，定时任务可直接用）：
     python x_comments_external.py <cmd> --api http://<account_sys地址>:<端口> \
          --email <登录邮箱> --password <登录密码> --account-id <账号ID>
     （内部先调 POST /api/v1/auth/login 换 Bearer，再调 GET /api/v1/x_tokens/latest，
       服务器端过期会自动刷新，拿到的永远是当前有效 token）

  B. 手动导出一次性 token（2 小时有效期）：
     bundle exec rails runner "a = Account.find(<account_id>); puts XAuthService.access_token_for(a)"
     然后通过 --token 传入，或设置环境变量 X_ACCESS_TOKEN

测试命令：
  python x_comments_external.py me                                    # 验证 token + 查自己的 x_user_id
  python x_comments_external.py my-tweets <x_user_id> [--count 5]     # 我的最近推文（拿 tweet_id）
  python x_comments_external.py tweet <tweet_id>                       # 查看单条推文
  python x_comments_external.py replies <tweet_id> [search|replies]  # 读推文下的回复（两种端点）
  python x_comments_external.py reply <tweet_id> 回复内容...          # 回复某条推文/评论（需 y 确认）
  python x_comments_external.py like <tweet_id>                       # 点赞实测（无 like.write scope 预期 403）
  python x_comments_external.py token                                 # 仅拉取并打印最新 token（配合定时任务缓存）

示例（从服务器拉 token 后读回复）：
  python x_comments_external.py replies 1848000000000000000 --api http://1.2.3.4:3000 \
       --email admin@test.com --password 123456 --account-id 471
"""

import argparse
import json
import os
import sys

import requests

API = "https://api.twitter.com"

TWEET_FIELDS = {
    "tweet.fields": "created_at,author_id,conversation_id,in_reply_to_user_id",
    "expansions": "author_id",
    "user.fields": "username,name",
}


def headers(token):
    return {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}


def show(resp):
    """打印完整响应：状态码 + JSON，方便观察套餐/权限报错细节"""
    print(f"HTTP {resp.status_code}")
    try:
        print(json.dumps(resp.json(), indent=2, ensure_ascii=False))
    except ValueError:
        print(resp.text[:500])


def print_tweets(resp):
    body = resp.json()
    users = {u["id"]: u for u in body.get("includes", {}).get("users", [])}
    for t in body.get("data", []):
        u = users.get(t.get("author_id"), {})
        print(f"  [{t['id']}] @{u.get('username', t.get('author_id'))} "
              f"at={t.get('created_at')} | {t.get('text', '')[:80]}")


def fetch_token_from_api(api, email, password, account_id=None):
    """登录 account_sys → 调 x_tokens/latest 拿最新 access_token（服务器端自动刷新）"""
    base = api.rstrip("/")
    r = requests.post(f"{base}/api/v1/auth/login", json={"email": email, "password": password})
    if r.status_code != 200:
        sys.exit(f"登录失败: HTTP {r.status_code} {r.text[:200]}")
    bearer = r.json()["data"]["token"]

    params = {"account_id": account_id} if account_id else {}
    r = requests.get(f"{base}/api/v1/x_tokens/latest",
                     headers={"Authorization": f"Bearer {bearer}"}, params=params)
    body = r.json()
    if r.status_code != 200 or body.get("code") != 200:
        sys.exit(f"拉取 token 失败: {r.text[:300]}")

    data = body["data"]
    if isinstance(data, list):
        # 未指定 account_id 时返回全量列表
        print(json.dumps(data, indent=2, ensure_ascii=False))
        sys.exit(0)
    return data


def main():
    parser = argparse.ArgumentParser(description="X 评论互动外部测试")
    parser.add_argument("cmd", choices=["me", "my-tweets", "tweet", "replies", "reply", "like", "token"])
    parser.add_argument("args", nargs="*", help="tweet_id / x_user_id / 回复内容")
    parser.add_argument("--token", default=os.environ.get("X_ACCESS_TOKEN"), help="access_token（或环境变量 X_ACCESS_TOKEN）")
    parser.add_argument("--count", type=int, default=5)
    parser.add_argument("--api", default=os.environ.get("ACCOUNT_SYS_API"), help="account_sys 地址（如 http://1.2.3.4:3000）")
    parser.add_argument("--email", default=os.environ.get("ACCOUNT_SYS_EMAIL"), help="account_sys 登录邮箱")
    parser.add_argument("--password", default=os.environ.get("ACCOUNT_SYS_PASSWORD"), help="account_sys 登录密码")
    parser.add_argument("--account-id", type=int, default=os.environ.get("ACCOUNT_SYS_ACCOUNT_ID") and int(os.environ["ACCOUNT_SYS_ACCOUNT_ID"]),
                        help="要拉 token 的 X 账号 ID（account_sys 内的账号 id）")
    opts = parser.parse_args()

    # token 来源：优先服务器拉取（自动刷新），否则用 --token / 环境变量
    token = opts.token
    if opts.api:
        if not (opts.email and opts.password):
            sys.exit("用 --api 拉取 token 需要 --email / --password（或对应环境变量）")
        data = fetch_token_from_api(opts.api, opts.email, opts.password, opts.account_id)
        token = data["access_token"]
        print(f"# 已从服务器拉取 token：账号={data.get('account_name')} "
              f"x_user_id={data.get('x_user_id')} 过期时间={data.get('token_expires_at')}", file=sys.stderr)

    if opts.cmd == "token":
        if not token:
            sys.exit("缺少 token 来源（--api 参数组 或 --token）")
        print(token)
        return

    if not token:
        sys.exit("缺少 token 来源：用 --api 参数组（自动拉取，推荐）或 --token / 环境变量 X_ACCESS_TOKEN")
    h = headers(token)

    if opts.cmd == "me":
        show(requests.get(f"{API}/2/users/me", headers=h))

    elif opts.cmd == "my-tweets":
        if not opts.args:
            sys.exit("用法: my-tweets <x_user_id> [--count 5]（x_user_id 可先跑 me 查到）")
        params = dict(TWEET_FIELDS, max_results=min(opts.count, 100))
        show(requests.get(f"{API}/2/users/{opts.args[0]}/tweets", headers=h, params=params))

    elif opts.cmd == "tweet":
        show(requests.get(f"{API}/2/tweets/{opts.args[0]}", headers=h, params=TWEET_FIELDS))

    elif opts.cmd == "replies":
        tweet_id, method = opts.args[0], (opts.args[1] if len(opts.args) > 1 else "search")
        params = dict(TWEET_FIELDS, max_results=100)
        if method == "search":
            # 方式 A：conversation_id 反查（经典，兼容性好；只覆盖最近 7 天，受套餐读取额度限制）
            params["query"] = f"conversation_id:{tweet_id}"
            url = f"{API}/2/tweets/search/recent"
        elif method == "replies":
            # 方式 B：X 新端点（可用性随套餐，403 就换 search）
            url = f"{API}/2/tweets/{tweet_id}/replies"
        else:
            sys.exit("方式只能选 search / replies")
        resp = requests.get(url, headers=h, params=params)
        show(resp)
        if resp.ok:
            print(f"\n拉到 {len(resp.json().get('data', []))} 条：")
            print_tweets(resp)

    elif opts.cmd == "reply":
        if len(opts.args) < 2:
            sys.exit("用法: reply <tweet_id> 回复内容...")
        tweet_id, text = opts.args[0], " ".join(opts.args[1:])
        print(f"将公开回复 {tweet_id}，内容：{text}")
        if input("确认发布？(y/n): ").strip().lower() != "y":
            sys.exit("已取消")
        payload = {"text": text, "reply": {"in_reply_to_tweet_id": tweet_id}}
        show(requests.post(f"{API}/2/tweets", headers=h, data=json.dumps(payload)))

    elif opts.cmd == "like":
        # 点赞需要 like.write scope，account_sys 现有授权未包含，预期 403
        if not opts.args:
            sys.exit("用法: like <tweet_id>")
        show(requests.post(f"{API}/2/users/me/likes", headers=h,
                            data=json.dumps({"tweet_id": opts.args[0]})))


if __name__ == "__main__":
    main()
