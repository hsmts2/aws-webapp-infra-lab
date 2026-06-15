
# aws-webapp-infra-lab

『AWSではじめるインフラ構築入門［第2版］』の学習内容をもとに、Webアプリケーション基盤を AWS CloudFormation で再現するためのリポジトリです。

本リポジトリは、書籍で学習した AWS インフラ構成を、自分の理解に基づいて Infrastructure as Code として整理したものです。  
書籍内容を転載するものではなく、学習した構成を CloudFormation テンプレート、補助スクリプト、構成メモとして再現・管理することを目的としています。

## 関連ドキュメント

| ドキュメント | 内容 |
|---|---|
| [docs/architecture.md](docs/architecture.md) | AWS構成、書籍構成との差分、設計意図 |
| [docs/deployment.md](docs/deployment.md) | CloudFormationデプロイ、SSH設定、アプリ導入、SES設定、エラー対応、削除手順 |

---

<br>

## 概要

書籍では AWS マネジメントコンソールを中心に、VPC・サブネット・NATゲートウェイ・踏み台サーバー・Webサーバー・ALB・RDS・S3・Route 53・ACM・SES・ElastiCacheなどを手作業で構築します。

本リポジトリでは、このうち CloudFormation で再現しやすいインフラ部分を IaC 化しています。  
SES とサンプルアプリについては、手順メモと補助スクリプトとして分離して管理します。

---

<br>

## 作成する構成

```text
Internet
  ↓
Application Load Balancer
  ↓ HTTP:3000
Puma / Rails on EC2（web01 / web02）
  ├─ RDS MySQL（マスターパスワードは Secrets Manager 管理）
  ├─ S3
  ├─ ElastiCache Redis
  └─ SES ※CloudFormation対象外（手順メモで管理）
```

確定構成では、ALB は Nginx ではなく Rails/Puma の `3000` 番ポートへ直接転送します。
そのため、ターゲットグループのポートは `3000` を標準とします。

Rails 側で CSS などの静的ファイルを返すため、アプリ起動時に `RAILS_SERVE_STATIC_FILES=1` が必須です。

---

<br>

## リポジトリ構成

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
    ├── architecture.md     # 構成の説明＋書籍との差分
    └── deployment.md       # デプロイ／SSH／SES／エラー対応／削除
```

---

<br>

## CloudFormation テンプレートで作成する主なリソース

| 分類             | 作成するリソース                                                                  |
| -------------- | ------------------------------------------------------------------------- |
| Network        | VPC、Public/Private Subnet（各2）、Internet Gateway、NAT Gateway（2）、Route Table |
| Security       | Security Group（elb / bastion / web / db / elasticache）                    |
| Compute        | Bastion EC2、Web EC2 01、Web EC2 02                                         |
| IAM            | Web サーバー用 IAM Role / Instance Profile                                     |
| Load Balancing | Application Load Balancer、Target Group（HTTP:3000）、Listener                |
| Database       | Amazon RDS for MySQL（Private サブネット配置）                                     |
| Storage        | Amazon S3（画像アップロード用）                                                      |
| Cache          | Amazon ElastiCache for Redis                                              |
| DNS            | Route 53 Private Hosted Zone（home）とレコード                                   |
| Secret         | Secrets Manager による RDS マスターパスワード管理                                       |
| Parameter      | Systems Manager Parameter Store への主要値・Secret ARN 保存                       |
| 任意             | ACM 証明書、HTTPS:443 リスナー、公開 Route 53 レコード（ドメイン指定時のみ）                        |


---

<br>

## RDS パスワード

RDS マスターパスワードは `ManageMasterUserPassword: true` により **Secrets Manager** が自動生成・管理します。
CloudFormation は Secret 本体ではなく、その **Secret ARN** を Systems Manager Parameter Store（`/<ProjectName>/rds/master-secret-arn`）に保存します。

これにより、RDS マスターパスワードがテンプレートやデプロイログに平文で残らない構成にしています。

なお、Secrets Manager で管理されるのは RDS マスターユーザー（`admin`）の認証情報です。
Rails アプリケーションが接続に使用する `sample_app` ユーザーのパスワードは、DB 初期化時に別途設定し、アプリケーションの環境変数 `AWS_INTRO_SAMPLE_DATABASE_PASSWORD` に設定します。

---

<br>

## ドメイン・ACM・公開レコードの扱い

`DomainName` と `PublicHostedZoneId` を **両方指定したときだけ**、ACM証明書・HTTPS:443 リスナー・HTTP→HTTPSリダイレクト・公開 Route 53 レコードが作成されます。

既定（両方とも空）では、これらは **作成されません**。
学習用途では空のままデプロイし、ALB の DNS 名に HTTP でアクセスする最小構成にできます。

---

<br>

## 書籍との差分
主な差分は以下の通りです。

| 項目              | 書籍・手作業             | 本リポジトリ                           |
| --------------- | ------------------ | -------------------------------- |
| RDSマスターパスワード    | 手動設定               | Secrets Manager で自動生成・管理         |
| RDS Secret 参照   | 手元で管理              | Parameter Store に Secret ARN を保存 |
| 各種エンドポイント       | 手動でメモ              | Parameter Store に保存              |
| S3 権限           | AmazonS3FullAccess | 既定は対象バケット限定（最小権限）                |
| ALB ターゲットポート    | 3000               | 既定 3000                          |
| Ruby / nokogiri | 2.6.6 / 1.10.10    | 2.7.8 / 1.11.7（経年差分対応）           |
| SES             | 手動設定               | 手順メモで管理                          |
| サンプルアプリ         | 手動構築               | scripts/ と docs/ に分離             |

---

<br>

## 事前準備

| 項目                   | 内容                                                |
| -------------------- | ------------------------------------------------- |
| AWS CLI              | インストール済み（`aws --version`）                         |
| AWS 認証情報             | `aws configure` 済み（`aws sts get-caller-identity`） |
| EC2 キーペア             | 作成済み（既定名 `sample-key`）                            |
| グローバル IP             | 踏み台SSH許可元（`YourIpCidr` に /32 推奨）                  |
| Route 53 Hosted Zone | 独自ドメインを使う場合のみ作成済み                                 |

---

<br>

## デプロイ方法

```bash
# パラメータ準備
cp parameters/study.example.env parameters/study.env
vi parameters/study.env

# 構文チェック
aws cloudformation validate-template \
  --template-body file://templates/aws-webapp-infra-lab.yaml

# コメント行を除外してパラメータを読み込み
PARAMS=$(grep -v '^#' parameters/study.env | xargs)

# デプロイ
aws cloudformation deploy \
  --template-file templates/aws-webapp-infra-lab.yaml \
  --stack-name aws-webapp-infra-lab \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides $PARAMS
```

---

<br>

## サンプルアプリについて
Ruby、Bundler、Rails、Gem 依存、Puma、DB 接続、CSS 配信、SES 送信設定など OS 内部の手順が多く、テンプレートに含めると保守性が下がるためです。

アプリ導入は `scripts/` のスクリプトと `docs/` の手順メモに分離しています。
EC2 の UserData では Ruby/Rails/Gem のインストールやコンパイルは行いません。

```text
ALB
  ↓ HTTP:3000
Puma / Rails
```

```bash
# 起動形（バックグラウンド）
nohup bundle _1.17.3_ exec rails server -e production -b 0.0.0.0 -p 3000 > log/puma.log 2>&1 &

# CSSが崩れる場合の確認
echo $RAILS_SERVE_STATIC_FILES   # 期待値: 1
```

---

<br>

## セキュリティ上の注意

以下はコミットしないでください（`.gitignore` でも除外済み）。

```text
秘密鍵（*.pem）
AWS アクセスキー
RDS パスワード
SES SMTP ユーザー名 / パスワード
SECRET_KEY_BASE
実際の .bash_profile
実際のパラメータファイル（parameters/study.env）
実値版の 06-configure-env.sh / 05-create-sample-app-db.sql
```

GitHub に置く場合は、マスクした example ファイルとして管理します。

```text
AWS_INTRO_SAMPLE_SMTP_USERNAME='YOUR_SES_SMTP_USERNAME'
AWS_INTRO_SAMPLE_SMTP_PASSWORD='YOUR_SES_SMTP_PASSWORD'
SECRET_KEY_BASE='YOUR_SECRET_KEY_BASE'
```

必要に応じてSES SMTP 用 IAM ユーザーのアクセスキーを無効化・削除してください。

---

<br>

## 削除方法

```bash
aws cloudformation delete-stack \
  --stack-name aws-webapp-infra-lab
```

削除完了を待機します。

```bash
aws cloudformation wait stack-delete-complete \
  --stack-name aws-webapp-infra-lab
```
<br>
