#!/bin/bash
# 04-deploy-sample-app.sh
# 実行ユーザー: deploy
# 目的: サンプルアプリを取得し、Gem依存を解決して assets をプリコンパイルする。
# 対象: Webサーバー（web01 / web02）
#
# 前提:
#   - 03-install-ruby.sh 実行済み（Ruby 2.7.8 / Bundler 1.17.3）
#   - 06-configure-env.sh で環境変数を設定済み、または本スクリプト後に設定する
#     （precompile時に SECRET_KEY_BASE 等が必要なため、先に 06 を実行推奨）
#
# 使い方:
#   sudo su - deploy
#   source ~/.bash_profile
#   bash 04-deploy-sample-app.sh
#
# 備考（書籍からの変更点・ハマり対策）:
#   - nokogiri は書籍の 1.10.10 をやめ、1.11.7 プリコンパイル版を入れてから
#     bundle update する。1.10.10 はソースビルド時に新glibcの canonicalize と
#     衝突してコンパイル失敗するため。

set -euo pipefail

APP_DIR="/var/www/aws-intro-sample-2nd"
REPO_URL="https://github.com/nakaken0629/aws-intro-sample-2nd.git"
BUNDLER_VERSION="1.17.3"
NOKOGIRI_VERSION="1.11.7"

export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init -)"

echo "==> アプリ取得（既にあればpull）"
if [ -d "${APP_DIR}/.git" ]; then
  cd "${APP_DIR}"
  git pull --ff-only || true
else
  cd /var/www
  git clone "${REPO_URL}"
  cd "${APP_DIR}"
fi

echo "==> Gemfile.lock の BUNDLED WITH 確認"
tail -3 Gemfile.lock || true

echo "==> nokogiri ${NOKOGIRI_VERSION} プリコンパイル版を導入"
gem install nokogiri -v "${NOKOGIRI_VERSION}"

echo "==> bundle update nokogiri（全Gem解決）"
bundle "_${BUNDLER_VERSION}_" update nokogiri

echo "==> bundle install（念のため全体を確定）"
bundle "_${BUNDLER_VERSION}_" install

echo "==> assets:precompile（production）"
# SECRET_KEY_BASE など本番用の環境変数が必要。未設定なら 06 を先に実行すること。
bundle "_${BUNDLER_VERSION}_" exec rails assets:precompile RAILS_ENV=production

echo "==> 完了: アプリ配置・依存解決・assetsプリコンパイル"
echo "    次に 06-configure-env（未実施なら）→ 07-start-puma の順で進める"
