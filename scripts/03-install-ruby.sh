#!/bin/bash
# 03-install-ruby.sh
# 実行ユーザー: deploy
# 目的: rbenv と Ruby 2.7.8、Bundler 1.17.3 を導入する。
# 対象: Webサーバー（web01 / web02）
#
# 使い方:
#   sudo su - deploy
#   bash 03-install-ruby.sh
#
# 備考（書籍からの変更点）:
#   - 書籍のRuby 2.6.6はやめて 2.7.8 を使う。2.6系では最新bundler/nokogiri等が
#     「Ruby >= 3.2 が必要」で弾かれるため。Rails 5.1が動く範囲で2.7.8を採用。
#   - bundlerは Gemfile.lock の BUNDLED WITH に合わせ 1.17.3 を明示インストール。
#     無指定だと最新4.x系が入り、依存解決に失敗する。

set -euo pipefail

RUBY_VERSION="2.7.8"
BUNDLER_VERSION="1.17.3"

echo "==> rbenv 導入（既にあればスキップ）"
if [ ! -d "$HOME/.rbenv" ]; then
  curl -fsSL https://github.com/rbenv/rbenv-installer/raw/HEAD/bin/rbenv-installer | bash
fi

echo "==> .bash_profile に rbenv 初期化を追記（重複追記を避ける）"
grep -q 'rbenv/bin' ~/.bash_profile 2>/dev/null || \
  echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bash_profile
grep -q 'rbenv init' ~/.bash_profile 2>/dev/null || \
  echo 'eval "$(rbenv init -)"' >> ~/.bash_profile

export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init -)"

echo "==> Ruby ${RUBY_VERSION} 導入（既にあればスキップ）"
if ! rbenv versions --bare | grep -qx "${RUBY_VERSION}"; then
  rbenv install "${RUBY_VERSION}"
fi
rbenv global "${RUBY_VERSION}"
rbenv rehash

echo "==> Ruby バージョン確認"
ruby -v

echo "==> Bundler ${BUNDLER_VERSION} 導入"
gem install bundler -v "${BUNDLER_VERSION}"
rbenv rehash

echo "==> 完了: Ruby ${RUBY_VERSION} / Bundler ${BUNDLER_VERSION}"
echo "    以降 bundle は必ず 'bundle _${BUNDLER_VERSION}_ <cmd>' の形で実行する"
