# architecture.md — 構成の説明と書籍との差分

『AWSではじめるインフラ構築入門 第2版』の構成を CloudFormation で再現したもの。
このドキュメントは「何を・なぜ」その構成にしているか、および書籍との差分を説明する。
手順は [deployment.md](deployment.md) を参照。

## 全体構成

```text
Internet
  │
  ├─（HTTP:80）  ドメイン未設定時 → ALB がそのままターゲットへ転送
  └─（HTTPS:443）ドメイン設定時   → ALB が HTTPS終端、80はHTTPSへリダイレクト
                                      ※ACM証明書・公開Route53は任意（既定では作らない）
  ↓
Application Load Balancer（sample-elb / public subnet × 2）
  ↓ HTTP:3000   ★Nginxを経由せず Puma に直結
Web EC2（web01 / web02、private subnet × 2）で Puma/Rails が稼働
  ├─ RDS for MySQL（sample-db、private subnet、Secrets Managerでパスワード管理）
  ├─ S3（画像アップロード用バケット）
  └─ ElastiCache for Redis（sample-elasticache、2シャード/2レプリカ）

SES はメール送受信に使うが、本番アクセス申請やSMTP認証情報が絡むため
CloudFormationでは作らず、手順メモとアプリ側の環境変数で扱う。
```

## ネットワーク

| 項目 | 値 | 備考 |
|---|---|---|
| VPC CIDR | 10.0.0.0/16 | 書籍と同じ |
| Public Subnet 01 / 02 | 10.0.0.0/20 / 10.0.16.0/20 | ap-northeast-1a / 1c |
| Private Subnet 01 / 02 | 10.0.64.0/20 / 10.0.80.0/20 | ap-northeast-1a / 1c |
| NAT Gateway | 2つ（各AZに1つ） | sample-ngw-01 / sample-ngw-02 |
| Route Table | public 共通1つ、private はAZごとに分離 | private01→ngw-01、private02→ngw-02 |

RDS は書籍に合わせて **Private サブネット**（private01 / private02）に配置する。
DB専用サブネット層は作らない（書籍構成に忠実）。

## セキュリティグループ

| SG | インバウンド | 用途 |
|---|---|---|
| sample-sg-elb | 80, 443（0.0.0.0/0） | ALB |
| sample-sg-bastion | 22（YourIpCidr） | 踏み台 |
| sample-sg-web | 22（bastionから）, 80/3000（ALBから） | Web |
| sample-sg-db | 3306（webから） | RDS |
| sample-sg-elasticache | 6379（webから） | Redis |

> 書籍の手作業構成ではWeb SGに3000番が無い場合があるが、本テンプレートでは
> ALBがPumaに直結するため、Web SGに 3000番（ソース=ALB SG）を明示的に開けている。

## ALB と Puma 直結（重要）

ターゲットグループ `sample-tg` のプロトコル:ポートは **HTTP:3000**。
ALB は Nginx(80) ではなく **Puma(3000) に直接** トラフィックを送る。

この構成では、CSS等の静的ファイルを **Rails自身が配信する** 必要があるため、
アプリ起動時に `RAILS_SERVE_STATIC_FILES=1` が必須。これが無いとCSSが404になる。
詳細は [deployment.md](deployment.md) のトラブルシューティングを参照。

## RDS パスワードの管理

`ManageMasterUserPassword: true` により、パスワードは **Secrets Manager** が
自動生成・管理する。CloudFormation は Secret 本体ではなく、その **ARN(参照)** を
SSM Parameter Store（`/<ProjectName>/rds/master-secret-arn`）に保存する。

- メリット: パスワードがテンプレートやログに平文で残らない。ローテーションも可能。
- アプリ側は、SSMからARN→Secrets Managerから実パスワードを取得して `.bash_profile` に設定する。

## SSM Parameter Store に保存する値

アプリ側の環境変数設定を楽にするため、主要な値をSSMに保存している。

| パラメータ名 | 内容 |
|---|---|
| /<ProjectName>/rds/master-secret-arn | RDSマスター認証情報のSecret ARN |
| /<ProjectName>/rds/endpoint | RDSエンドポイント |
| /<ProjectName>/s3/image-bucket | 画像バケット名 |
| /<ProjectName>/elasticache/endpoint | Redis設定エンドポイント |
| /<ProjectName>/alb/dns-name | ALBのDNS名 |

## プライベートDNS（home ゾーン）

VPC内専用の Route 53 プライベートホストゾーン `home` を作成し、以下を登録する。
アプリは `db.home` 等の名前で各サービスを参照する。

| レコード | 種別 | 向き先 |
|---|---|---|
| bastion.home | A | 踏み台のプライベートIP |
| web01.home / web02.home | A | 各WebのプライベートIP |
| db.home | CNAME | RDSエンドポイント |
| cache.home | CNAME | Redis設定エンドポイント |

## 任意（ドメイン運用時のみ作成）

`DomainName` と `PublicHostedZoneId` を両方指定したときだけ作成される。
既定（空）では作られない。

- ACM証明書（www.<domain> のDNS検証）
- HTTPS:443 リスナー
- HTTP:80 → HTTPS リダイレクト
- 公開Route53レコード（www.<domain>、bastion.<domain>）

## CloudFormation で作らないもの（意図的）

| 項目 | 理由 |
|---|---|
| SES（ドメイン検証・SMTP認証情報・本番アクセス申請） | UI操作・申請が絡むため手順メモで管理 |
| サンプルアプリ本体（Ruby/Rails/Gem/Puma） | OS内部手順が多く、scripts/ と docs/ に分離 |
| Route 53 ドメイン登録（取得） | ドメイン取得はCloudFormation対象外 |

---

# 書籍構成との差分

書籍の手作業構成を基本としつつ、IaC として安全・再利用しやすくするために調整した点。

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

## アプリ導入をUserDataに含めない理由

第13章のアプリ導入は、Ruby・Bundler・nokogiri・Puma・DB接続・CSS配信・SES設定など
OS内部の手順が多く、失敗時の再実行やデバッグが頻繁に発生する。これをUserDataに
詰め込むと、失敗のたびにインスタンス作り直しが必要になり保守性が下がる。

そのため、インフラ（CloudFormation）とアプリ構築（scripts/*.sh）を分離している。
UserDataは `yum update` 程度の最小限に留め、Ruby/Rails/Gemのインストールや
コンパイルは一切行わない。
