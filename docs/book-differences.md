# book-differences.md — 書籍構成との差分

書籍『AWSではじめるインフラ構築入門 第2版』の手作業構成を基本としつつ、
IaC として安全・再利用しやすくするために調整した点をまとめる。

## 構成の差分

| 項目 | 書籍・手作業 | 本リポジトリ | 理由 |
|---|---|---|---|
| リソース名 | sample-* | ProjectName=sample で再現 | 書籍の命名を踏襲 |
| サブネット | Public 2 / Private 2 | 同じ（4サブネット） | 書籍準拠（DB専用サブネットは作らない） |
| RDS配置 | Privateサブネット | 同じ（Privateサブネット） | 書籍準拠 |
| NAT Gateway | 2つ（各AZ） | 2つ（sample-ngw-01/02） | 書籍準拠（冗長構成を学ぶ意図） |
| Private Route Table | AZごとに分離 | 同じ（private01/02を分離） | 書籍準拠 |
| ALBターゲットポート | 3000 | 既定3000（80も選択可） | 確定構成（ALB→Puma直結） |
| Web SG 3000番 | 手作業では曖昧な場合あり | ALB SGから3000を明示許可 | Puma直結に必要 |

## セキュリティ・運用面の差分

| 項目 | 書籍・手作業 | 本リポジトリ | 理由 |
|---|---|---|---|
| RDSパスワード | 手動で任意の文字列 | Secrets Manager で自動生成・管理 | 平文を残さない。ローテーション可 |
| RDS Secret参照 | 手元管理 | SSM Parameter Store に Secret ARN を保存 | アプリ側から参照しやすく |
| 各種エンドポイント | 手動でメモ | SSM Parameter Store に保存 | 環境変数設定の自動化 |
| S3 IAM権限 | AmazonS3FullAccess | 既定は対象バケット限定（最小権限）。BookFullAccessで書籍同等も選べる | 最小権限の原則 |
| RDS削除時 | - | DeletionPolicy: Snapshot | 誤削除時の復旧 |
| S3削除時 | - | DeletionPolicy: Retain | 誤削除防止 |

## 現行AWS仕様に合わせた変更

| 項目 | 書籍 | 本リポジトリ | 理由 |
|---|---|---|---|
| Ruby | 2.6.6 | 2.7.8 | 2.6系は最新bundler/nokogiri等が動かない |
| Bundler | （古い既定） | 1.17.3 明示 | Gemfile.lockのBUNDLED WITHに準拠 |
| nokogiri | 1.10.10 | 1.11.7→解決後1.15.7 | glibc衝突回避（プリコンパイル版） |
| RDSクラス | db.t2.micro | 既定 db.t3.micro（t2も選択可） | t2系が新規で使いにくいため |
| ストレージ | （汎用SSD） | gp3 | 現行の標準 |

## CloudFormationで作らないもの（意図的）

| 項目 | 扱い |
|---|---|
| SES（ドメイン検証・SMTP認証・本番申請） | 手順メモ（setup-notes.md） |
| サンプルアプリ本体（Ruby/Rails/Gem/Puma） | scripts/web/ と docs/ |
| Route 53 ドメイン取得（登録） | 対象外 |
| ACM・HTTPS・公開Route53レコード | 任意（DomainName指定時のみ作成。既定は作らない） |

## アプリ導入をUserDataに含めない理由

第13章のアプリ導入は、Ruby・Bundler・nokogiri・Puma・DB接続・CSS配信・SES設定など
OS内部の手順が多く、失敗時の再実行やデバッグが頻繁に発生する。これをUserDataに
詰め込むと、失敗のたびにインスタンス作り直しが必要になり保守性が下がる。

そのため、インフラ（CloudFormation）とアプリ構築（scripts/web/*.sh）を分離している。
UserDataは `yum update` 程度の最小限に留め、Ruby/Rails/Gemのインストールや
コンパイルは一切行わない。
