#!/bin/bash
# 01-install-middleware.sh
# 実行ユーザー: ec2-user（sudoを使用）
# 目的: Railsのビルド・実行・画像処理に必要なOSパッケージを導入する。
# 対象: Webサーバー（web01 / web02）
#
# 使い方:
#   bash 01-install-middleware.sh
#
# 備考:
#   - nodejs は Amazon Linux 2 のyumに無いが、assets:precompileは通るため不要。
#   - libcurl-devel は fog→ovirt-engine-sdk のビルドに必須（入れ忘れるとbundleで失敗）。

set -euo pipefail

echo "==> yum update"
sudo yum update -y

echo "==> Railsビルド・実行に必要なパッケージ"
sudo yum install -y \
  git \
  gcc \
  gcc-c++ \
  make \
  openssl-devel \
  readline-devel \
  zlib-devel \
  mysql-devel \
  ImageMagick \
  ImageMagick-devel

echo "==> ハマり対策の追加パッケージ"
# fog→ovirt-engine-sdk が libcurl を要求する
sudo yum install -y libcurl-devel
# nokogiri等のXML処理（最終的に必須ではないが入れて害なし）
sudo yum install -y libxml2-devel libxslt-devel

echo "==> nginx（任意。ALBがPuma直結の構成では必須ではない）"
# 静的配信をNginxに任せたい場合のみ。Puma直結のみで運用するなら不要。
# sudo amazon-linux-extras install nginx1 -y
# sudo systemctl enable nginx
# sudo systemctl start nginx

echo "==> 完了: ミドルウェア導入"
