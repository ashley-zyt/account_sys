# postforme 授权 + 发布接口使用说明（供本地 agent）

本文档说明如何通过 account_sys 的接口，为外部的账号完成 postforme 授权（获取 `social_account_id`），并据此发布内容。整套流程的 `POSTFORME_API_KEY` 只存在服务器端，本地 agent 不接触 key，避免凭证外露。

## 一、这套接口解决什么

postforme 是第三方发布平台，一个 `POSTFORME_API_KEY` 可以管理多个平台的多个社交账号。

每个社交账号要发布，需要先完成一次 **OAuth 授权**，拿到该账号在 postforme 里的 `social_account_id`。授权是「生成链接 → 人工浏览器点授权 → 反查 social_account_id」的一次性异步流程。

本接口把授权 + 发布流程包成一组 HTTP 接口，供本地 agent 调用。**不依赖 account_sys 的 Account 表**，全程用 `external_id` 来标识「这是谁的哪个账号」。

## 二、external_id 约定（重要）

`external_id` 是「谁的账号」的唯一标识，由使用方自己填，只要保证**唯一**即可。

推荐格式：`所属人-平台-账号名`

示例：

| 所属人 | 平台        | 账号  | external_id        |
| --- | --------- | --- | ------------------ |
| 张三  | youtube   | 美食号 | `张三-youtube-美食号`   |
| 李四  | instagram | 穿搭号 | `李四-instagram-穿搭号` |

> 具体怎么填由你自定，唯一即可。同一个 external_id 再次授权会覆盖之前那次（postforme 侧按 external_id 关联）。

## 三、接口概览

| 接口                                 | 方法   | 作用                        | 入参                                                                  |
| ---------------------------------- | ---- | ------------------------- | ------------------------------------------------------------------- |
| `/api/v1/auth/login`               | POST | 登录拿 token                 | `email` + `password`                                                |
| `/api/v1/postforme_agent/auth_url` | POST | 生成授权链接                    | `platform` + `external_id`                                          |
| `/api/v1/postforme_agent/status`   | GET  | 查授权状态                     | `external_id`                                                       |
| `/api/v1/postforme_agent/confirm`  | POST | 确认授权（拿 social_account_id） | `external_id`                                                       |
| `/api/v1/postforme_agent/publish`  | POST | 发布内容                      | `social_account_id` + `caption` + `media_urls` / `media_files`（可选）等 |

除 `auth/login` 外，其余接口都需要在请求头带 `Authorization: Bearer <token>`。

## 四、完整使用流程

### 1. 登录拿 token

```bash
curl -X POST http://<host>/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"your@email.com","password":"your_password"}'
```

返回：

```json
{
  "code": 200,
  "msg": "登录成功",
  "data": { "token": "<token>", "expires_in": 86400 }
}
```

后续请求都带 `Authorization: Bearer <token>`。token 有效期 24 小时，过期重新登录即可。

### 2. 生成授权链接

```bash
curl -X POST http://<host>/api/v1/postforme_agent/auth_url \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"platform":"youtube","external_id":"张三-youtube-美食号"}'
```

返回：

```json
{
  "code": 200,
  "msg": "success",
  "data": {
    "platform": "youtube",
    "external_id": "张三-youtube-美食号",
    "auth_url": "https://postforme.dev/oauth/authorize?xxx"
  }
}
```

拿到 `auth_url` 后，发给对应所属人，让他在浏览器打开并完成授权。

### 3. 查授权状态（可选）

所属人授权完成后，可以先查一下状态：

```bash
curl "http://<host>/api/v1/postforme_agent/status?external_id=张三-youtube-美食号" \
  -H "Authorization: Bearer <token>"
```

返回（未授权）：

```json
{ "code": 200, "msg": "success", "data": { "external_id": "张三-youtube-美食号", "auth_status": "pending", "social_account_id": null } }
```

返回（已授权）：

```json
{ "code": 200, "msg": "success", "data": { "external_id": "张三-youtube-美食号", "auth_status": "authorized", "social_account_id": "spc_xxxx" } }
```

### 4. 确认授权（拿 social_account_id）

```bash
curl -X POST http://<host>/api/v1/postforme_agent/confirm \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"external_id":"张三-youtube-美食号"}'
```

返回（成功）：

```json
{ "code": 200, "msg": "success", "data": { "external_id": "张三-youtube-美食号", "social_account_id": "spc_xxxx" } }
```

返回（还没授权，会返回 409）：

```json
{ "code": 409, "msg": "授权未完成，请先在浏览器完成 OAuth 后重试" }
```

拿到 `social_account_id` 后，这个账号就授权完成，后续发布用这个 `social_account_id` 即可。

### 5. 发文

拿到 `social_account_id` 后，即可发布内容。媒体支持两种来源：

- **线上链接**（`media_urls`）：视频/图片已有公开 URL 时用
- **本地文件**：大视频推荐「直传 OSS 脚本」，小文件可用 `media_files`（multipart）

**方式一：传线上链接（JSON）**

```bash
curl -X POST http://<host>/api/v1/postforme_agent/publish \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "social_account_id": "spc_xxxx",
    "caption": "今天这条标题",
    "media_urls": ["https://oss.xxx/video.mp4"]
  }'
```

**方式二：本地视频——推荐用直传 OSS 脚本（避免大文件超时）**

大视频经过 account_sys 中转容易超时，推荐用脚本**直传阿里云 OSS**（不经过 account_sys，稳定且每步有明确结果）。脚本不依赖 account_sys 项目目录，**全文见附录八**，可拷贝到任何机器落盘为 `postforme_publish.py` 直接执行：

```bash
pip install requests

python postforme_publish.py \
  --host http://<host> --email xx@xx.com --password 123 \
  --social-account-id spc_xxx --caption "标题" \
  --video /path/to/video.mp4
```

脚本内部自动完成「登录 → 拿凭证 → 直传 OSS → 发布」四步，每步打印成功/失败，失败会给出具体原因。也支持线上链接 + 本地文件混用（`--media-url` 可传多个）。

**方式三：小文件直接用 multipart 上传（media_files）**

图片或小文件可用这个，但**大视频容易超时**，建议改用上面的直传脚本：

```bash
curl -X POST http://<host>/api/v1/postforme_agent/publish \
  -H "Authorization: Bearer <token>" \
  -F "social_account_id=spc_xxxx" \
  -F "caption=今天这条标题" \
  -F "media_files=@/path/to/local/video.mp4"
```

返回（成功）：

```json
{ "code": 200, "msg": "success", "data": { "post_id": "...", "social_account_id": "spc_xxxx" } }
```

参数说明：

| 参数                  | 必填 | 说明                          |
| ------------------- | -- | --------------------------- |
| `social_account_id` | 是  | 授权拿到的 social_account_id     |
| `caption`           | 是  | 标题/正文                       |
| `media_urls`        | 否  | 媒体公开 URL 数组（也可传逗号分隔字符串）     |
| `media_files`       | 否  | 本地媒体文件（multipart 表单字段，可传多个） |
| `external_id`       | 否  | 本系统任务标识（用于关联）               |
| `scheduled_at`      | 否  | 定时发布，ISO8601 UTC            |

纯图文（不带视频）时，`media_urls` / `media_files` 都留空即可。

## 五、平台取值

`platform` 参数取值：`youtube` / `facebook` / `instagram` / `tiktok` / `twitter`。

> 注意：twitter 在 postforme 内部叫 `x`，接口内部会自动做映射，你直接传 `twitter` 即可，不用管。

## 六、错误码说明

| HTTP 状态 | code | 含义                                          |
| ------- | ---- | ------------------------------------------- |
| 401     | 401  | 缺少 token / token 无效或过期                      |
| 400     | 400  | 缺少必要参数（platform / external_id 为空）           |
| 409     | 409  | 授权未完成（confirm 时还没在浏览器授权）                    |
| 502     | 502  | 调 postforme 失败，或本地媒体文件上传 OSS 失败（看 msg 里的描述） |

## 七、注意事项

1. **授权是一次性的**：一个 external_id 授权成功后，`social_account_id` 长期有效，不用重复授权。除非 postforme 侧解绑，才需要重新授权。
2. **external_id 要保持唯一**：同一个 external_id 再次生成授权链接，会关联到之前那次授权。
3. **social_account_id 存在 postforme 侧**：本系统不落地记录，agent 需要时随时用 `status` / `confirm` 反查即可。
4. **授权链接有时效**：`auth_url` 生成后建议尽快让所属人完成授权，避免链接失效。
5. **本地文件会先传 OSS**：传 `media_files` 时，服务端先把文件上传到 OSS（bucket `operation-viodes`）拿到公开链接，再交给 postforme。视频较大时上传会慢一些，属正常。
6. **OSS 下载链接有时效**：本地文件上传后生成的下载链接默认 180 天有效，postforme 在发布那一刻去抓取，只要发布时没过期即可。

## 八、附录：直传 + 发布脚本全文（postforme_publish.py）

> 可拷贝到任意机器落盘为 `postforme_publish.py` 直接使用，仅依赖 `requests`（`pip install requests`）。  
> 脚本已内置：不受本机 HTTP_PROXY 环境影响（强制直连）、Windows 下 UTF-8 输出、兼容 OSS 直传返回 200/204。

```python
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
postforme 直传 + 发布脚本（供本地 agent 使用）

封装「登录 → 拿上传凭证 → 直传 OSS → 发布」完整流程，解决两个问题：
  1. 本地大视频经过 account_sys 中转容易超时 —— 改为直传阿里云 OSS（不经过 account_sys）
  2. 超时后不知道是否成功 —— 每步都有明确成功/失败提示，失败会打印具体原因

依赖：pip install requests

用法：
  # 本地视频发布（直传 OSS）
  python postforme_publish.py --host http://<host> --email xx@xx.com --password 123 \
      --social-account-id spc_xxx --caption "标题" --video /path/to/video.mp4

  # 线上链接发布（不传 --video）
  python postforme_publish.py --host http://<host> --email xx@xx.com --password 123 \
      --social-account-id spc_xxx --caption "标题" --media-url "https://xxx/video.mp4"

  # 可同时传多个线上链接、或本地视频 + 线上链接混用
  python postforme_publish.py ... --video a.mp4 --media-url "https://x/1.jpg" --media-url "https://x/2.jpg"
"""

import argparse
import os
import sys

import requests

# Windows 控制台按 GBK 解码会打爆中文输出，固定 stdout 为 UTF-8
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

# 不受本机 HTTP_PROXY/HTTPS_PROXY 环境变量影响（沙箱/代理环境下直连更稳）
_SESSION = requests.Session()
_SESSION.trust_env = False


def login(host, email, password):
    resp = _SESSION.post(
        f"{host}/api/v1/auth/login",
        json={"email": email, "password": password},
        timeout=30,
    )
    data = resp.json()
    if data.get("code") != 200:
        raise RuntimeError(f"登录失败：{data.get('msg')}")
    print("[1/4] 登录成功")
    return data["data"]["token"]


def get_upload_signature(host, token, filename):
    resp = _SESSION.post(
        f"{host}/api/v1/oss/upload_signature",
        json={"filename": filename},
        timeout=30,
    )
    data = resp.json()
    if data.get("type") != "success":
        raise RuntimeError(f"拿上传凭证失败：{data.get('message')}")
    print(f"[2/4] 已获取上传凭证（对象 key={data['data']['key']}）")
    return data["data"]


def upload_to_oss(sig, video_path):
    size_mb = os.path.getsize(video_path) / 1024 / 1024
    print(f"[3/4] 开始直传 OSS：{os.path.basename(video_path)}（{size_mb:.1f} MB），请稍候...")

    with open(video_path, "rb") as f:
        data = {
            "key": sig["key"],
            "OSSAccessKeyId": sig["accessKeyId"],
            "policy": sig["policy"],
            "signature": sig["signature"],
        }
        resp = _SESSION.post(
            sig["endpoint"],
            data=data,
            files={"file": (os.path.basename(video_path), f)},
            timeout=3600,  # 大文件上传给足时间
        )

    # OSS 表单直传（PostObject）成功时返回 200 或 204（无 callback 时 204），两者都算成功
    if resp.status_code not in (200, 204):
        raise RuntimeError(f"直传 OSS 失败：HTTP {resp.status_code}，{resp.text[:300]}")
    print("[3/4] 直传 OSS 成功")
    return sig["url"]


def publish(host, token, social_account_id, caption, media_urls, scheduled_at=None):
    body = {
        "social_account_id": social_account_id,
        "caption": caption,
        "media_urls": media_urls,
    }
    if scheduled_at:
        body["scheduled_at"] = scheduled_at

    resp = _SESSION.post(
        f"{host}/api/v1/postforme_agent/publish",
        headers={"Authorization": f"Bearer {token}"},
        json=body,
        timeout=60,
    )
    data = resp.json()
    if data.get("code") != 200:
        raise RuntimeError(f"发布失败：{data.get('msg')}")
    print(f"[4/4] 发布成功，post_id={data['data']['post_id']}")
    return data["data"]["post_id"]


def main():
    parser = argparse.ArgumentParser(description="postforme 直传 + 发布脚本")
    parser.add_argument("--host", required=True, help="account_sys 地址，如 http://1.2.3.4")
    parser.add_argument("--email", required=True, help="登录邮箱")
    parser.add_argument("--password", required=True, help="登录密码")
    parser.add_argument("--social-account-id", required=True, help="授权拿到的 social_account_id")
    parser.add_argument("--caption", required=True, help="标题/正文")
    parser.add_argument("--video", help="本地视频/图片路径（可选）")
    parser.add_argument("--media-url", action="append", default=[], help="线上链接（可多次传）")
    parser.add_argument("--scheduled-at", help="定时发布，ISO8601 UTC（可选）")
    args = parser.parse_args()

    if not args.video and not args.media_url:
        print("错误：--video 或 --media-url 至少传一个", file=sys.stderr)
        sys.exit(1)

    try:
        token = login(args.host, args.email, args.password)

        media_urls = list(args.media_url)
        if args.video:
            if not os.path.isfile(args.video):
                raise RuntimeError(f"本地文件不存在：{args.video}")
            sig = get_upload_signature(args.host, token, os.path.basename(args.video))
            media_urls.append(upload_to_oss(sig, args.video))

        publish(args.host, token, args.social_account_id, args.caption, media_urls, args.scheduled_at)
        print("\n完成。")
    except Exception as e:
        print(f"\n失败：{e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
```


```
```
