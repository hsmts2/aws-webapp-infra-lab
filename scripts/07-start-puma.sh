#!/bin/bash
# 07-start-puma.sh
# 実行ユーザー: deploy
# 目的: Puma を本番モードでバックグラウンド起動し、CSS配信まで確認する。
# 対象: Webサーバー（web01 / web02）
#
# 前提:
#   - 04 で assets:precompile 済み
#   - 05 で環境変数設定済み（特に RAILS_SERVE_STATIC_FILES=1）
#
# 使い方:
#   sudo su - deploy
#   source ~/.bash_profile
#   bash 07-start-puma.sh
#
# 備考（ハマり対策）:
#   - フォアグラウンド起動（rails serverを素で実行）だと、別コマンドを打とうと
#     Ctrl+Cした瞬間にPumaが死ぬ。必ず nohup ... & でバックグラウンド起動する。
#   - ALBがPuma(3000)に直結しているため、RAILS_SERVE_STATIC_FILES=1 が無いと
#     CSSが404になる。起動前に必ず 1 が出ることを確認する。

set -euo pipefail

APP_DIR="/var/www/aws-intro-sample-2nd"
BUNDLER_VERSION="1.17.3"
PORT="3000"

export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init -)"

cd "${APP_DIR}"

echo "==> 環境変数チェック"
if [ "${RAILS_SERVE_STATIC_FILES:-}" != "1" ]; then
  echo "    [警告] RAILS_SERVE_STATIC_FILES が 1 ではありません（現在: '${RAILS_SERVE_STATIC_FILES:-未設定}'）"
  echo "    CSSが404になります。06-configure-env を見直し、source ~/.bash_profile してください。"
  echo "    今回はコマンドに直接付与して起動を続行します。"
fi

echo "==> 既存Pumaの停止（動いていれば）"
if [ -f tmp/pids/server.pid ]; then
  OLD_PID="$(cat tmp/pids/server.pid)"
  if kill -0 "${OLD_PID}" 2>/dev/null; then
    kill "${OLD_PID}"
    sleep 2
    echo "    旧Puma(PID ${OLD_PID})を停止しました"
  fi
  rm -f tmp/pids/server.pid
fi

echo "==> Puma 起動（nohup バックグラウンド）"
RAILS_SERVE_STATIC_FILES=1 RAILS_ENV=production \
  nohup bundle "_${BUNDLER_VERSION}_" exec rails server -e production -b 0.0.0.0 -p "${PORT}" \
  > log/puma.log 2>&1 &

echo "==> 起動待機"
sleep 5

echo "==> プロセス確認"
ps aux | grep -v grep | grep puma || echo "    [警告] Pumaプロセスが見つかりません。log/puma.log を確認してください。"

echo "==> トップページ応答確認（Puma直 3000）"
curl -sI "http://localhost:${PORT}/" | head -1 || true

echo "==> CSS配信確認（★200 OK text/css になれば成功）"
CSS_FILE="$(ls public/assets/ 2>/dev/null | grep -E '^application-.*\.css$' | head -1 || true)"
if [ -n "${CSS_FILE}" ]; then
  curl -sI "http://localhost:${PORT}/assets/${CSS_FILE}" | head -3 || true
else
  echo "    [警告] public/assets に application-*.css がありません。04 の precompile を確認。"
fi

echo "==> 完了: Puma起動"
echo "    ALBに登録するのは、上のCSS確認が 200 になってから（unhealthy/502回避）"
