#!/bin/zsh
# ダブルクリックで tunneld と GUI を起動する（tunneld の起動に管理者パスワードが必要）
cd "$(dirname "$0")"
VENV="$PWD/.venv"
if [ ! -x "$VENV/bin/python" ]; then
  python3 -m venv "$VENV" && "$VENV/bin/pip" install -q pymobiledevice3
fi

if ! curl -s -m 2 http://127.0.0.1:49151 >/dev/null; then
  echo "tunneld を起動します（管理者パスワードを入力してください）"
  sudo -b "$VENV/bin/pymobiledevice3" remote tunneld >/dev/null 2>&1
  for i in {1..20}; do curl -s -m 1 http://127.0.0.1:49151 >/dev/null && break; sleep 1; done
fi

"$VENV/bin/python" server.py
