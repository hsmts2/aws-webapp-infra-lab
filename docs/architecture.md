# architecture.md — 構成の説明

『AWSではじめるインフラ構築入門 第2版』の構成を CloudFormation で再現したもの。
このドキュメントは「何を・なぜ」その構成にしているかを説明する。手順は `deployment.md` を参照。

## 全体構成

```
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
詳細は `troubleshooting.md` を参照。

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

## CloudFormation で作らないもの

| 項目 | 理由 |
|---|---|
| SES（ドメイン検証・SMTP認証情報・本番アクセス申請） | UI操作・申請が絡むため手順メモで管理 |
| サンプルアプリ本体（Ruby/Rails/Gem/Puma） | OS内部手順が多く、scripts/ と docs/ に分離 |
| Route 53 ドメイン登録（取得） | ドメイン取得はCloudFormation対象外 |
| 詳細なCloudWatchダッシュボード | 基本アラームのみ作成、詳細は手順メモ |
