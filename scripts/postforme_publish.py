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
