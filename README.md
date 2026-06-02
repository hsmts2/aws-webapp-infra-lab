# aws-webapp-infra-lab

『AWSではじめるインフラ構築入門［第2版］』の学習内容をもとに、Webアプリケーション基盤を AWS CloudFormation で再現するためのリポジトリです。

本リポジトリは、書籍で学習した AWS インフラ構成を、自分の理解に基づいて Infrastructure as Code として整理したものです。  
書籍内容を転載するものではなく、学習した構成を CloudFormation テンプレート、補助スクリプト、構成メモとして再現・管理することを目的としています。

---

<br>

## 概要

本リポジトリでは、AWS 上に Web アプリケーション基盤を構築するための主要リソースを CloudFormation で管理します。

書籍では AWS マネジメントコンソールを中心に、以下のような構成を手作業で構築します。

- VPC
- パブリックサブネット
- プライベートサブネット
- インターネットゲートウェイ
- NAT ゲートウェイ
- 踏み台サーバー
- Web サーバー
- Application Load Balancer
- RDS for MySQL
- S3
- Route 53
- ACM
- Amazon SES
- ElastiCache for Redis
- CloudWatch
- Billing and Cost Management

本リポジトリでは、これらのうち CloudFormation で再現しやすい AWS インフラ部分を中心に IaC 化しています。

---

<br>

## 作成する構成

CloudFormation テンプレートでは、主に以下の構成を作成します。

```text
Internet
  ↓
Route 53 / ACM
  ↓
Application Load Balancer
  ↓ HTTP:3000
Puma / Rails on EC2
  ├─ RDS MySQL
  ├─ S3
  ├─ ElastiCache Redis
  └─ SES ※別途手動設定
```

今回の確定手順では、ALB は Nginx ではなく Rails/Puma の `3000` 番ポートへ直接転送します。
そのため、ターゲットグループのポートは `3000` を標準とします。

```text
ブラウザ
  ↓ HTTPS:443
ALB
  ↓ HTTP:3000
Puma / Rails
```

Rails 側で CSS などの静的ファイルを返すため、アプリ起動時には以下の環境変数が重要です。

```bash
export RAILS_SERVE_STATIC_FILES=1
```

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
│   ├── web/
│   │   ├── 01-install-middleware.sh
│   │   ├── 02-create-deploy-user.sh
│   │   ├── 03-install-ruby.sh
│   │   ├── 04-deploy-sample-app.sh
│   │   ├── 05-configure-env.sh.example
│   │   └── 06-start-puma.sh
│   └── db/
│       └── create-sample-app-db.sql.example
├── docs/
│   ├── architecture.md
│   ├── deployment.md
│   ├── setup-notes.md
│   ├── troubleshooting.md
│   ├── cost-cleanup.md
│   └── book-differences.md
└── diagrams/
    └── aws-webapp-infra-lab.drawio
```

---

<br>

## CloudFormation テンプレート

CloudFormation テンプレートは以下に配置します。

```text
templates/aws-webapp-infra-lab.yaml
```

このテンプレートでは、主に以下の AWS リソースを作成します。

| 分類 | 作成するリソース |
|---|---|
| Network | VPC、Subnet、Internet Gateway、NAT Gateway、Route Table |
| Security | Security Group |
| Compute | Bastion EC2、Web EC2 01、Web EC2 02 |
| IAM | Web サーバー用 IAM Role / Instance Profile |
| Load Balancing | Application Load Balancer、Target Group、Listener |
| Database | Amazon RDS for MySQL |
| Storage | Amazon S3 |
| Cache | Amazon ElastiCache for Redis OSS |
| DNS | Route 53 Public / Private Hosted Zone Records |
| Certificate | AWS Certificate Manager |
| Monitoring | CloudWatch Alarm |
| Secret | Secrets Manager による RDS パスワード管理 |
| Parameter | Systems Manager Parameter Store への主要値保存 |

---

<br>

## 書籍構成との対応

| 書籍の章 | 内容 | 本リポジトリでの扱い |
|---|---|---|
| 第4章 | VPC 作成 | CloudFormation で作成 |
| 第5章 | 踏み台サーバー | CloudFormation で作成 |
| 第6章 | Web サーバー | CloudFormation で作成 |
| 第7章 | ロードバランサー | CloudFormation で作成 |
| 第8章 | RDS | CloudFormation で作成 |
| 第9章 | S3 | CloudFormation で作成 |
| 第10章 | Route 53 / ACM | CloudFormation で作成 |
| 第11章 | SES | 手順メモとして管理 |
| 第12章 | ElastiCache | CloudFormation で作成 |
| 第13章 | サンプルアプリ | 補助スクリプト・手順メモとして管理 |
| 第14章 | CloudWatch | 一部 CloudFormation 化、詳細は手順メモ |
| 第15章 | コスト管理 | 手順メモとして管理 |

---

<br>

## 書籍との差分

本リポジトリでは、書籍の構成を基本としつつ、IaC として安全・再利用しやすくするために一部を調整しています。

| 項目 | 書籍・手作業構成 | 本リポジトリ |
|---|---|---|
| リソース名 | `sample-*` | `ProjectName=sample` により再現 |
| サブネット | Public 2つ、Private 2つ | 同様に4サブネット構成 |
| NAT Gateway | 2つ | `sample-ngw-01` / `sample-ngw-02` を作成 |
| Private Route Table | Private 01 / 02 で分離 | 同様に分離 |
| ALB ターゲットポート | `3000` | デフォルト `3000` |
| RDS パスワード | 手動設定 | Secrets Manager で自動生成・管理 |
| RDS Secret 参照 | 手元で管理 | Parameter Store に Secret ARN を保存 |
| S3 権限 | `AmazonS3FullAccess` | デフォルトは対象バケット限定権限 |
| SES | 手動設定 | 本番アクセス申請や SMTP 認証情報が絡むため手順メモで管理 |
| サンプルアプリ | 手動構築 | 確定手順を `scripts/` と `docs/` に分離 |

---

<br>

## 事前準備

デプロイ前に、以下を準備しておきます。

| 項目 | 内容 |
|---|---|
| AWS CLI | ローカル PC にインストール済みであること |
| AWS 認証情報 | `aws configure` などで設定済みであること |
| EC2 キーペア | 事前に作成済みであること |
| Route 53 Hosted Zone | 独自ドメインを使う場合は作成済みであること |
| グローバル IP | 踏み台サーバーへの SSH 許可元として使用 |

AWS CLI の確認例です。

```bash
aws --version
```

認証確認です。

```bash
aws sts get-caller-identity
```

---

<br>

## パラメータ

本テンプレートの主要パラメータは以下です。

| パラメータ | 例 | 内容 |
|---|---|---|
| `ProjectName` | `sample` | リソース名の接頭辞。書籍に合わせるため `sample` を推奨 |
| `KeyName` | `sample-key` | EC2 接続用キーペア名 |
| `YourIpCidr` | `xxx.xxx.xxx.xxx/32` | 踏み台サーバーへの SSH 許可元 |
| `DomainName` | `zexample.com` | 使用する独自ドメイン |
| `PublicHostedZoneId` | `Zxxxxxxxxxxxxx` | Route 53 のパブリックホストゾーン ID |
| `AlbTargetPort` | `3000` | ALB から Web サーバーへ転送するポート |
| `S3AccessMode` | `LeastPrivilege` | S3 権限の付与方式 |

`EnvironmentName` は使用しません。書籍の命名に合わせて、リソース名は `sample-*` で統一します。

---

<br>

## パラメータ例

AWS CLI の `deploy` コマンドで使いやすいように、以下のような env 形式のパラメータファイルを用意します。

```text
parameters/study.example.env
```

例です。

```text
ProjectName=sample
KeyName=sample-key
YourIpCidr=xxx.xxx.xxx.xxx/32
DomainName=zexample.com
PublicHostedZoneId=Z123456789ABCDEFG
AlbTargetPort=3000
S3AccessMode=LeastPrivilege
```

実際に使う場合は、このファイルをコピーして編集します。

```bash
cp parameters/study.example.env parameters/study.env
```

`parameters/study.env` は個人環境情報を含むため、Git 管理しません。

JSON 形式の例です。

```json
[
  {
    "ParameterKey": "ProjectName",
    "ParameterValue": "sample"
  },
  {
    "ParameterKey": "KeyName",
    "ParameterValue": "sample-key"
  },
  {
    "ParameterKey": "YourIpCidr",
    "ParameterValue": "xxx.xxx.xxx.xxx/32"
  },
  {
    "ParameterKey": "DomainName",
    "ParameterValue": "zexample.com"
  },
  {
    "ParameterKey": "PublicHostedZoneId",
    "ParameterValue": "Z123456789ABCDEFG"
  },
  {
    "ParameterKey": "AlbTargetPort",
    "ParameterValue": "3000"
  },
  {
    "ParameterKey": "S3AccessMode",
    "ParameterValue": "LeastPrivilege"
  }
]
```

---

<br>

## デプロイ方法

CloudFormation スタックを作成します。

```bash
aws cloudformation deploy \
  --template-file templates/aws-webapp-infra-lab.yaml \
  --stack-name aws-webapp-infra-lab \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides $(cat parameters/study.env)
```

テンプレートの構文を事前に確認する場合は、以下を実行します。

```bash
aws cloudformation validate-template \
  --template-body file://templates/aws-webapp-infra-lab.yaml
```

---

<br>

## スタックの確認

スタックの状態を確認します。

```bash
aws cloudformation describe-stacks \
  --stack-name aws-webapp-infra-lab
```

出力値を確認します。

```bash
aws cloudformation describe-stacks \
  --stack-name aws-webapp-infra-lab \
  --query "Stacks[0].Outputs"
```

---

<br>

## 作成後に確認すること

CloudFormation でインフラを作成した後、以下を確認します。

| 確認項目 | 内容 |
|---|---|
| VPC | `sample-vpc` が作成されていること |
| Subnet | Public 2つ、Private 2つが作成されていること |
| NAT Gateway | `sample-ngw-01`, `sample-ngw-02` が作成されていること |
| EC2 | Bastion、Web01、Web02 が作成されていること |
| ALB | ALB と Target Group が作成されていること |
| Target Group | ターゲットポートが `3000` であること |
| RDS | MySQL DB インスタンスが作成されていること |
| S3 | 画像保存用バケットが作成されていること |
| ElastiCache | Redis OSS クラスターが作成されていること |
| Route 53 | Public / Private DNS レコードが作成されていること |
| Secrets Manager | RDS マスターパスワードが管理されていること |
| Parameter Store | 主要エンドポイント情報が保存されていること |

---

<br>

## SSH 接続

踏み台サーバーへ接続します。

```bash
ssh -i path/to/key.pem ec2-user@bastion.zexample.com
```

ドメインを使わない場合は、CloudFormation Outputs に表示される Bastion Public IP を使います。

```bash
ssh -i path/to/key.pem ec2-user@<BastionPublicIp>
```

Web サーバーへは踏み台経由で接続します。

```bash
ssh web01
```

```bash
ssh web02
```

SSH 設定例は `docs/setup-notes.md` に記録します。

---

<br>

## サンプルアプリについて

第13章のサンプルアプリは、CloudFormation では完全自動化していません。

理由は、Ruby、Bundler、Rails、Gem 依存、Puma、DB 接続、CSS 配信、SES 送信設定など、OS 内部の手順が多く、CloudFormation テンプレートにすべて含めると保守性が下がるためです。

アプリ導入手順は以下に分離します。

```text
scripts/web/
docs/setup-notes.md
docs/troubleshooting.md
```

確定構成は以下です。

```text
ALB
  ↓ HTTP:3000
Puma / Rails
```

アプリ起動は、最終的に以下のような形を想定します。

```bash
nohup bundle _1.17.3_ exec rails server -e production -b 0.0.0.0 -p 3000 > log/puma.log 2>&1 &
```

CSS が崩れる場合は、以下が設定されているか確認します。

```bash
echo $RAILS_SERVE_STATIC_FILES
```

期待値は以下です。

```text
1
```

---

<br>

## セキュリティ上の注意

このリポジトリには、以下の情報をコミットしないでください。

```text
秘密鍵
AWS アクセスキー
RDS パスワード
SES SMTP ユーザー名
SES SMTP パスワード
SECRET_KEY_BASE
実際の .bash_profile
実際のパラメータファイル
.env
個人情報
```

特に、第13章の作業ログには SES SMTP 認証情報や `SECRET_KEY_BASE` が含まれやすいため、GitHub にはそのまま載せません。

GitHub に置く場合は、以下のようにマスクした example ファイルとして管理します。

```text
AWS_INTRO_SAMPLE_SMTP_USERNAME='YOUR_SES_SMTP_USERNAME'
AWS_INTRO_SAMPLE_SMTP_PASSWORD='YOUR_SES_SMTP_PASSWORD'
SECRET_KEY_BASE='YOUR_SECRET_KEY_BASE'
```

---

<br>

## 削除方法

学習完了後は、料金発生を防ぐためにリソースを削除します。

```bash
aws cloudformation delete-stack \
  --stack-name aws-webapp-infra-lab
```

削除状況を確認します。

```bash
aws cloudformation describe-stacks \
  --stack-name aws-webapp-infra-lab
```

削除後も、以下の残存リソースがないか確認します。

| リソース | 注意点 |
|---|---|
| RDS Snapshot | `DeletionPolicy: Snapshot` により残る場合がある |
| S3 Bucket | `DeletionPolicy: Retain` により残る場合がある |
| Secrets Manager Secret | 削除保留期間がある |
| Route 53 Hosted Zone | 手動作成した Hosted Zone は残る |
| CloudWatch Logs | ロググループが残る場合がある |
| EIP | 未使用 EIP が残っていないか確認する |
| NAT Gateway | 削除漏れがあると課金が続く |
| ElastiCache | ノード数が多いため削除漏れに注意 |

---

<br>

## 学習メモ

このリポジトリは、単に AWS リソースを作成するだけでなく、以下を整理することも目的としています。

- 書籍で作成した構成の理解
- CloudFormation による再現
- 手作業と IaC の違い
- 現行 AWS 仕様との差分
- トラブルシュート履歴
- コスト削減と削除手順
- GitHub ポートフォリオとしての整理

---

<br>

## 今後の改善案

今後、以下を追加する予定です。

- 第13章サンプルアプリ導入スクリプト
- `.bash_profile` 用の環境変数 example
- Puma systemd 設定
- DB 初期化 SQL
- CloudWatch ダッシュボード定義
- 構成図
- 削除手順の詳細化
- GitHub Actions による CloudFormation テンプレート検証

---

<br>

## 参考

- 『AWSではじめるインフラ構築入門［第2版］』
- AWS CloudFormation
- Amazon VPC
- Amazon EC2
- Elastic Load Balancing
- Amazon RDS
- Amazon S3
- Amazon Route 53
- AWS Certificate Manager
- Amazon SES
- Amazon ElastiCache
- Amazon CloudWatch
