# aws-webapp-infra-lab

『AWSではじめるインフラ構築入門［第2版］』の学習内容をもとに、Webアプリケーション基盤を AWS CloudFormation で再現するためのリポジトリです。

本リポジトリは、書籍で学習した AWS インフラ構成を、自分の理解に基づいて Infrastructure as Code として整理したものです。
書籍内容を転載するものではなく、学習した構成を CloudFormation テンプレート、補助スクリプト、構成メモとして再現・管理することを目的としています。

---

<br>

## 概要

本リポジトリでは、AWS上にWebアプリケーション基盤を構築するための主要リソースを CloudFormation で管理します。

書籍では AWS マネジメントコンソールを中心に、以下のような構成を手作業で構築します。

* VPC
* パブリックサブネット
* プライベートサブネット
* インターネットゲートウェイ
* NATゲートウェイ
* 踏み台サーバー
* Webサーバー
* Application Load Balancer
* RDS for MySQL
* S3
* Route 53
* ACM
* Amazon SES
* ElastiCache for Redis
* CloudWatch

本リポジトリでは、これらのうち、AWSインフラとして再現しやすい部分をCloudFormation化しています。

---

<br>

## 作成する構成

CloudFormationテンプレートでは、主に以下の構成を作成します。

```text
Internet
  ↓
Route 53
  ↓
ACM / ALB
  ↓
Web EC2
  ↓
RDS / S3 / ElastiCache
```

より具体的には、以下のような構成です。

```text
VPC: sample-vpc
├─ Public Subnet 01
│  ├─ NAT Gateway 01
│  └─ Bastion EC2
│
├─ Public Subnet 02
│  └─ NAT Gateway 02
│
├─ Private Subnet 01
│  └─ Web EC2 01
│
└─ Private Subnet 02
   └─ Web EC2 02

ALB
├─ Target Group
└─ Listener

RDS
└─ MySQL

S3
└─ Image bucket

ElastiCache
└─ Redis OSS

Route 53
├─ zexample.com
├─ www.zexample.com
├─ bastion.zexample.com
└─ private hosted zone: home
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
│   │   ├── 02-install-ruby.sh
│   │   ├── 03-deploy-sample-app.sh
│   │   ├── 04-configure-nginx.sh
│   │   └── 05-start-puma.sh
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

## CloudFormationテンプレート

CloudFormationテンプレートは以下に配置します。

```text
templates/aws-webapp-infra-lab.yaml
```

このテンプレートでは、主に以下のAWSリソースを作成します。

| 分類             | 作成するリソース                                            |
| -------------- | --------------------------------------------------- |
| Network        | VPC、Subnet、Internet Gateway、NAT Gateway、Route Table |
| Security       | Security Group                                      |
| Compute        | EC2 Bastion、EC2 Web Server                          |
| Load Balancing | Application Load Balancer、Target Group、Listener     |
| Database       | Amazon RDS for MySQL                                |
| Storage        | Amazon S3                                           |
| Cache          | Amazon ElastiCache for Redis OSS                    |
| DNS            | Route 53 Public / Private Hosted Zone Records       |
| Certificate    | AWS Certificate Manager                             |
| Monitoring     | CloudWatch Alarm                                    |
| Secret         | Secrets ManagerによるRDSパスワード管理                        |
| Parameter      | Systems Manager Parameter Storeへの主要値保存              |

---

<br>

## 書籍構成との対応

| 書籍の章 | 内容             | 本リポジトリでの扱い                |
| ---- | -------------- | ------------------------- |
| 第4章  | VPC作成          | CloudFormationで作成         |
| 第5章  | 踏み台サーバー        | CloudFormationで作成         |
| 第6章  | Webサーバー        | CloudFormationで作成         |
| 第7章  | ロードバランサー       | CloudFormationで作成         |
| 第8章  | RDS            | CloudFormationで作成         |
| 第9章  | S3             | CloudFormationで作成         |
| 第10章 | Route 53 / ACM | CloudFormationで作成         |
| 第11章 | SES            | 手順メモとして管理                 |
| 第12章 | ElastiCache    | CloudFormationで作成         |
| 第13章 | サンプルアプリ        | 補助スクリプト・手順メモとして管理         |
| 第14章 | CloudWatch     | 一部CloudFormation化、詳細は手順メモ |
| 第15章 | コスト管理          | 手順メモとして管理                 |

---

<br>

## 書籍との差分

本リポジトリでは、書籍の構成を基本としつつ、IaCとして安全・再利用しやすくするために一部を調整しています。

| 項目          | 書籍                 | 本リポジトリ                                     |
| ----------- | ------------------ | ------------------------------------------ |
| RDSパスワード    | 手動設定               | Secrets Managerで自動生成・管理                    |
| RDSパスワード参照  | 手元で管理              | Parameter StoreにSecret ARNを保存              |
| S3権限        | AmazonS3FullAccess | デフォルトは対象バケット限定権限                           |
| Route 53    | 手動作成               | Public / Private DNSレコードをCloudFormationで作成 |
| ALBターゲットポート | 構成により3000番         | Nginx経由を想定し80番も指定可能                        |
| SES         | 手動設定               | 本番アクセス申請やSMTP認証情報が絡むため手順メモで管理              |

---

<br>

## 事前準備

デプロイ前に、以下を準備しておきます。

| 項目                   | 内容                           |
| -------------------- | ---------------------------- |
| AWS CLI              | ローカルPCにインストール済みであること         |
| AWS認証情報              | `aws configure` などで設定済みであること |
| EC2キーペア              | 事前に作成済みであること                 |
| Route 53 Hosted Zone | 独自ドメインを使う場合は作成済みであること        |
| グローバルIP              | 踏み台サーバーへのSSH許可元として使用         |

AWS CLIの確認例です。

```bash
aws --version
```

認証確認です。

```bash
aws sts get-caller-identity
```

---

<br>

## パラメータ例

AWS CLIの `deploy` コマンドで使いやすいように、以下のようなenv形式のパラメータファイルを用意します。

```text
parameters/study.example.env
```

例です。

```text
ProjectName=sample
EnvironmentName=study
KeyName=sample-key
YourIpCidr=xxx.xxx.xxx.xxx/32
DomainName=zexample.com
PublicHostedZoneId=Z123456789ABCDEFG
AlbTargetPort=80
S3AccessMode=LeastPrivilege
```

実際に使う場合は、このファイルをコピーして編集します。

```bash
cp parameters/study.example.env parameters/study.env
```

`parameters/study.env` は個人環境情報を含むため、Git管理しません。

---

<br>

## デプロイ方法

CloudFormationスタックを作成します。

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

CloudFormationでインフラを作成した後、以下を確認します。

| 確認項目            | 内容                                          |
| --------------- | ------------------------------------------- |
| VPC             | `sample-vpc` が作成されていること                     |
| Subnet          | Public 2つ、Private 2つが作成されていること              |
| NAT Gateway     | `sample-ngw-01`, `sample-ngw-02` が作成されていること |
| EC2             | Bastion、Web01、Web02 が作成されていること              |
| ALB             | ALBとTarget Groupが作成されていること                  |
| RDS             | MySQL DBインスタンスが作成されていること                    |
| S3              | 画像保存用バケットが作成されていること                         |
| ElastiCache     | Redis OSSクラスターが作成されていること                    |
| Route 53        | Public / Private DNSレコードが作成されていること          |
| Secrets Manager | RDSマスターパスワードが管理されていること                      |
| Parameter Store | 主要エンドポイント情報が保存されていること                       |

---

<br>

## SSH接続

踏み台サーバーへ接続します。

```bash
ssh -i path/to/key.pem ec2-user@bastion.zexample.com
```

ドメインを使わない場合は、CloudFormation Outputs に表示される Bastion Public IP を使います。

```bash
ssh -i path/to/key.pem ec2-user@<BastionPublicIp>
```

Webサーバーへは踏み台経由で接続します。

```bash
ssh web01
```

```bash
ssh web02
```

SSH設定例は `docs/setup-notes.md` に記録します。

---

<br>

## サンプルアプリについて

第13章のサンプルアプリは、CloudFormationでは完全自動化していません。

理由は、Ruby、Bundler、Rails、Gem依存、Nginx、Puma、DB接続、CSS配信など、OS内部の手順が多く、CloudFormationテンプレートにすべて含めると保守性が下がるためです。

そのため、アプリ導入手順は以下に分離します。

```text
scripts/web/
docs/setup-notes.md
docs/troubleshooting.md
```

第13章の最終構成は、以下を想定します。

```text
ALB
  ↓ HTTP:80
Nginx
  ↓ HTTP:3000
Puma / Rails
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

| リソース                   | 注意点                       |
| ---------------------- | ------------------------- |
| RDS Snapshot           | DeletionPolicyにより残る場合がある  |
| S3 Bucket              | オブジェクトが残っていると削除に失敗する場合がある |
| Secrets Manager Secret | 削除保留期間がある                 |
| Route 53 Hosted Zone   | 手動作成したHosted Zoneは残る      |
| CloudWatch Logs        | ロググループが残る場合がある            |
| EIP                    | 未使用EIPが残っていないか確認する        |

---

<br>

## 注意事項

このリポジトリには、以下の情報をコミットしないでください。

```text
秘密鍵
AWSアクセスキー
RDSパスワード
SES SMTPパスワード
実際のパラメータファイル
.env
個人情報
```

特に、以下のファイルはGit管理対象外にします。

```text
*.pem
.env
parameters/*.env
parameters/*.json
!parameters/*.example.json
```

---

<br>

## 学習メモ

このリポジトリは、単にAWSリソースを作成するだけでなく、以下を整理することも目的としています。

* 書籍で作成した構成の理解
* CloudFormationによる再現
* 手作業とIaCの違い
* 現行AWS仕様との差分
* トラブルシュート履歴
* コスト削減と削除手順
* GitHubポートフォリオとしての整理

---

<br>

## 今後の改善案

今後、以下を追加する予定です。

* 第13章サンプルアプリ導入スクリプト
* Nginx設定ファイル
* Puma systemd設定
* DB初期化SQL
* CloudWatchダッシュボード定義
* 構成図
* 削除手順の詳細化
* GitHub Actionsによるテンプレート検証

---

<br>

## 参考

* 『AWSではじめるインフラ構築入門［第2版］』
* AWS CloudFormation
* Amazon VPC
* Amazon EC2
* Elastic Load Balancing
* Amazon RDS
* Amazon S3
* Amazon Route 53
* AWS Certificate Manager
* Amazon SES
* Amazon ElastiCache
* Amazon CloudWatch
