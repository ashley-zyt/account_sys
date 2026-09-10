#!/usr/bin/env bash
# ==================== account_sys 重启脚本 ====================
# 用法:
#   ./restart.sh                            # 默认 development + 端口 3366
#   RAILS_ENV=production PORT=3366 ./restart.sh
#
# 说明:
#   - 优雅停止当前 Puma（读 pidfile），兜底清理占用端口的残留进程
#   - 后台重新启动，日志写入 log/restart_boot.log

set -e

cd "$(dirname "$0")"

# 加载 rvm 环境（cron / 非交互 shell 时保证 ruby 可用）
[[ -s "$HOME/.rvm/scripts/rvm" ]] && source "$HOME/.rvm/scripts/rvm" >/dev/null 2>&1 || true

APP_DIR="$(pwd)"
PID_FILE="$APP_DIR/tmp/pids/puma.pid"
PORT="${PORT:-3366}"
RAILS_ENV="${RAILS_ENV:-development}"
BOOT_LOG="$APP_DIR/log/restart_boot.log"

echo "===== 停止 Puma（环境=${RAILS_ENV}，端口=${PORT}）====="

# 1) 按 pidfile 优雅停止
if [ -f "$PID_FILE" ]; then
  PID="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    echo "  向主进程 ${PID} 发送 TERM ..."
    kill -TERM "$PID" 2>/dev/null || true
    for _ in $(seq 1 30); do
      kill -0 "$PID" 2>/dev/null || break
      sleep 1
    done
    if kill -0 "$PID" 2>/dev/null; then
      echo "  进程未退出，强制 KILL ..."
      kill -9 "$PID" 2>/dev/null || true
    fi
  fi
  rm -f "$PID_FILE"
else
  echo "  未找到 pid 文件，跳过"
fi

# 2) 兜底：清理占用端口的残留进程
if command -v fuser >/dev/null 2>&1; then
  fuser -k "${PORT}/tcp" >/dev/null 2>&1 || true
fi

sleep 2

echo "===== 启动 Puma ====="
mkdir -p "$APP_DIR/tmp/pids" "$APP_DIR/log"
nohup bundle exec rails s -u puma -e "$RAILS_ENV" -b 0.0.0.0 -p "$PORT" > "$BOOT_LOG" 2>&1 &

sleep 3

if [ -f "$PID_FILE" ]; then
  echo "✅ 启动成功（PID $(cat "$PID_FILE")）"
elif command -v curl >/dev/null 2>&1 && curl -s -o /dev/null "http://127.0.0.1:${PORT}/"; then
  echo "✅ 启动成功（端口 ${PORT} 可访问）"
else
  echo "⚠️ 未确认启动成功，请查看 ${BOOT_LOG}"
fi
