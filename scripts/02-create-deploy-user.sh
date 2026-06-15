#!/bin/bash
# 02-create-deploy-user.sh
# 実行ユーザー: ec2-user（sudoを使用）
# 目的: アプリ実行用の deploy ユーザーと配置先 /var/www を作成する。
# 対象: Webサーバー（web01 / web02）
#
# 使い方:
#   bash 02-create-deploy-user.sh
#
# 備考:
#   - 以降のアプリ操作（rbenv, bundle, rails）はすべて deploy ユーザーで行う。
#     ec2-userで実行すると bundle: command not found や using password: NO で詰まる。

set -euo pipefail

echo "==> deploy ユーザー作成（既に存在すればスキップ）"
if id deploy &>/dev/null; then
  echo "    deploy ユーザーは既に存在します"
else
  sudo adduser deploy
fi

echo "==> /var/www の作成と所有者設定"
sudo mkdir -p /var/www
sudo chown deploy:deploy /var/www

echo "==> 完了: deploy ユーザーと /var/www 準備"
echo "    次は deploy ユーザーに切り替えて 03 を実行:  sudo su - deploy"
