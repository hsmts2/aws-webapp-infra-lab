# aws-webapp-infra-lab

『AWSではじめるインフラ構築入門［第2版］』の学習内容をもとに、Webアプリケーション基盤を AWS CloudFormation で再現するためのリポジトリです。

本リポジトリは、書籍で学習した AWS インフラ構成を、自分の理解に基づいて Infrastructure as Code として整理したものです。書籍内容を転載するものではなく、学習した構成を CloudFormation テンプレート、補助スクリプト、構成メモとして再現・管理することを目的としています。

---

<br>

## 概要

書籍では AWS マネジメントコンソールを中心に、VPC・サブネット・NAT Gateway・踏み台サーバー・Webサーバー・ALB・RDS・S3・Route 53・ACM・SES・ElastiCache などを手作業で構築します。

本リポジトリでは、このうち CloudFormation で再現しやすいインフラ部分を IaC 化しています。SES とサンプルアプリについては、手順メモと補助スクリプトとして分離して管理します。

---

<br>

## 対象書籍と学習範囲

| 項目 | 内容 |
| --- | --- |
| 対象書籍 | AWSではじめるインフラ構築入門［第2版］ |
| 学習テーマ | AWS 上での Web アプリケーション基盤構築 |
| 主な学習対象 | VPC / EC2 / ALB / RDS / S3 / Route 53 / ACM / SES / ElastiCache |
| 本リポジトリで作成する範囲 | VPC / EC2 / ALB / RDS / S3 / ElastiCache / Secrets Manager / Systems Manager Parameter Store |
| 作成するAWS構成 | ALB + Web サーバー2台 + RDS + S3 + ElastiCache の Web アプリケーション基盤 |
| IaC | AWS CloudFormation |
| テンプレート形式 | YAML |
| リージョン | `ap-northeast-1` |

---

<br>

## リポジトリの目的

このリポジトリの目的は、単に CloudFormation テンプレートを保存することではなく、以下の観点を整理することです。

* AWS 上の Web アプリケーション基盤をコードとして再現する
* 手動構築した内容を CloudFormation に置き換える
* RDS パスワードや主要エンドポイントを安全に管理する
* ALB から Rails / Puma へ直接転送する構成を整理する
* サンプルアプリ導入手順をインフラ構築と分離して管理する
* GitHub 上で学習成果をポートフォリオとして管理する

---

<br>

## アーキテクチャ

構成の詳細、書籍構成との差分、設計意図は以下に整理しています。

| ドキュメント | 内容 |
| --- | --- |
| [docs/architecture.md](docs/architecture.md) | AWS構成、書籍構成との差分、設計意図 |
| [docs/deployment.md](docs/deployment.md) | CloudFormationデプロイ、SSH設定、アプリ導入、SES設定、エラー対応、削除手順 |

---

<br>

## 作成される構成

```text
Internet
  |
  | HTTP:80 / HTTPS:443
  v
Application Load Balancer
  |
  | HTTP:3000
  v
Puma / Rails on EC2 (web01 / web02)
  ├── RDS MySQL
  ├── S3
  ├── ElastiCache Redis
  └── SES
```

確定構成では、ALB は Nginx ではなく Rails / Puma の `3000` 番ポートへ直接転送します。そのため、ターゲットグループのポートは `3000` を標準とします。

Rails 側で CSS などの静的ファイルを返すため、アプリ起動時に `RAILS_SERVE_STATIC_FILES=1` が必須です。

---

<br>

## 作成される主な AWS リソース

| 分類 | 作成するリソース |
| --- | --- |
| Network | VPC、Public / Private Subnet（各2）、Internet Gateway、NAT Gateway（2）、Route Table |
| Security | Security Group（elb / bastion / web / db / elasticache） |
| Compute | Bastion EC2、Web EC2 01、Web EC2 02 |
| IAM | Web サーバー用 IAM Role / Instance Profile |
| Load Balancing | Application Load Balancer、Target Group（HTTP:3000）、Listener |
| Database | Amazon RDS for MySQL（Private サブネット配置） |
| Storage | Amazon S3（画像アップロード用） |
| Cache | Amazon ElastiCache for Redis |
| DNS | Route 53 Private Hosted Zone（home）とレコード |
| Secret | Secrets Manager による RDS マスターパスワード管理 |
| Parameter | Systems Manager Parameter Store への主要値・Secret ARN 保存 |
| 任意 | ACM 証明書、HTTPS:443 リスナー、公開 Route 53 レコード（ドメイン指定時のみ） |

---

<br>

## 本テンプレートで対象外にしたもの

| 対象外 | 理由 |
| --- | --- |
| SES | 本番アクセス申請、ドメイン検証、SMTP 認証情報の作成など手動対応が絡むため |
| サンプルアプリ本体 | Ruby、Bundler、Rails、Gem、Puma など OS 内部の手順が多いため |
| Route 53 ドメイン登録 | ドメイン取得は CloudFormation 対象外のため |

---

<br>

## ディレクトリ構成

```text
aws-webapp-infra-lab/
├── README.md
├── .gitignore
├── templates/
│   └── aws-webapp-infra-lab.yaml
├── parameters/
│   ├── study.example.env
│   └── study.example.json
├── scripts/
│   ├── 01-install-middleware.sh
│   ├── 02-create-deploy-user.sh
│   ├── 03-install-ruby.sh
│   ├── 04-deploy-sample-app.sh
│   ├── 05-create-sample-app-db.sql.example
│   ├── 06-configure-env.sh.example
│   └── 07-start-puma.sh
└── docs/
    ├── architecture.md
    └── deployment.md
```

---

<br>

## CloudFormation テンプレート

CloudFormation テンプレートは以下に格納しています。

[templates/aws-webapp-infra-lab.yaml](templates/aws-webapp-infra-lab.yaml)

このテンプレートでは、VPC、サブネット、踏み台サーバー、Web サーバー、ALB、RDS、S3、ElastiCache、Secrets Manager、Systems Manager Parameter Store などをまとめて作成します。

---

<br>

## パラメータファイル

パラメータファイルのサンプルは以下に格納しています。

| ファイル | 用途 |
| --- | --- |
| [parameters/study.example.env](parameters/study.example.env) | `aws cloudformation deploy` の `--parameter-overrides` で使用するサンプル |
| [parameters/study.example.json](parameters/study.example.json) | CloudFormation パラメータJSON形式のサンプル |

実際にデプロイする場合は、サンプルファイルをコピーして使用します。

```bash
cp parameters/study.example.env parameters/study.env
```

`parameters/study.env` には、自分の環境に合わせた値を設定します。実環境用の値を含むため、GitHub にはコミットしない運用とします。

---

<br>

## 前提条件

以下の環境が必要です。

* AWS CLI v2
* AWS CLI の認証設定済み環境
* デプロイ先 AWS アカウント
* デプロイ先リージョン: `ap-northeast-1`
* 既存の EC2 キーペア
* 独自ドメインを使用する場合のみ Route 53 Hosted Zone
* CloudFormation、EC2、VPC、IAM、ELB、RDS、S3、ElastiCache、Secrets Manager、Systems Manager 関連リソースを作成・更新・削除できる IAM 権限

---

<br>

## デプロイ・運用方法

### パラメータ準備

```bash
cp parameters/study.example.env parameters/study.env
vi parameters/study.env
```

### テンプレート検証

```bash
aws cloudformation validate-template \
  --template-body file://templates/aws-webapp-infra-lab.yaml
```

### スタック作成

```bash
PARAMS=$(grep -v '^#' parameters/study.env | xargs)

aws cloudformation deploy \
  --template-file templates/aws-webapp-infra-lab.yaml \
  --stack-name aws-webapp-infra-lab \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides $PARAMS
```

### スタック状態確認

```bash
aws cloudformation describe-stacks \
  --stack-name aws-webapp-infra-lab \
  --query "Stacks[0].Outputs" \
  --output table
```

### 動作確認

CloudFormation Outputs の `WebsiteUrl` または `AlbDnsName` にアクセスします。アプリケーション導入後は、ALB から Puma への転送と静的ファイル配信が正常であることを確認します。

### スタック更新

```bash
PARAMS=$(grep -v '^#' parameters/study.env | xargs)

aws cloudformation deploy \
  --template-file templates/aws-webapp-infra-lab.yaml \
  --stack-name aws-webapp-infra-lab \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides $PARAMS
```

### スタック削除

```bash
aws cloudformation delete-stack \
  --stack-name aws-webapp-infra-lab
```

削除完了を待機します。

```bash
aws cloudformation wait stack-delete-complete \
  --stack-name aws-webapp-infra-lab
```

---

<br>

## 設計上の補足

RDS マスターパスワードは `ManageMasterUserPassword: true` により Secrets Manager が自動生成・管理します。CloudFormation は Secret 本体ではなく、その Secret ARN を Systems Manager Parameter Store（`/<ProjectName>/rds/master-secret-arn`）に保存します。

`DomainName` と `PublicHostedZoneId` を両方指定したときだけ、ACM 証明書、HTTPS:443 リスナー、HTTP→HTTPS リダイレクト、公開 Route 53 レコードが作成されます。既定（両方とも空）では、これらは作成されません。

サンプルアプリの導入は `scripts/` のスクリプトと `docs/deployment.md` に分離しています。EC2 の UserData では Ruby / Rails / Gem のインストールやコンパイルは行いません。

実値を含むパラメータファイル、秘密鍵、AWS アクセスキー、RDS パスワード、SES SMTP 認証情報、`SECRET_KEY_BASE` は GitHub にコミットしない運用とします。公開する場合は、`<YOUR_SES_SMTP_USERNAME>` のようなプレースホルダーを使った example ファイルとして管理します。

---

<br>

## 書籍との差分

| 項目 | 書籍・手作業 | 本リポジトリ |
| --- | --- | --- |
| RDSマスターパスワード | 手動設定 | Secrets Manager で自動生成・管理 |
| RDS Secret 参照 | 手元で管理 | Parameter Store に Secret ARN を保存 |
| 各種エンドポイント | 手動でメモ | Parameter Store に保存 |
| S3 権限 | AmazonS3FullAccess | 既定は対象バケット限定（最小権限） |
| ALB ターゲットポート | 3000 | 既定 3000 |
| Ruby / nokogiri | 2.6.6 / 1.10.10 | 2.7.8 / 1.11.7（経年差分対応） |
| SES | 手動設定 | 手順メモで管理 |
| サンプルアプリ | 手動構築 | scripts/ と docs/ に分離 |
