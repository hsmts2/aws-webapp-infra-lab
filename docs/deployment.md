# deployment.md — デプロイ手順

CloudFormation でインフラを作成し、Webサーバーにアプリを導入するまでの流れ。

## 0. 事前準備

| 項目 | 内容 |
|---|---|
| AWS CLI | インストール済み（`aws --version`） |
| 認証情報 | `aws configure` 済み（`aws sts get-caller-identity` で確認） |
| EC2キーペア | 作成済み（既定名 `sample-key`） |
| グローバルIP | 踏み台SSH許可元。`YourIpCidr` に /32 で設定推奨 |
| ドメイン（任意） | 使う場合のみ Route 53 パブリックHostedZoneを用意 |

## 1. パラメータ準備

```bash
cp parameters/study.example.env parameters/study.env
vi parameters/study.env     # YourIpCidr などを実値に
```

ドメインを使わない場合は `DomainName` と `PublicHostedZoneId` を空のままにする
（ACM・HTTPS・公開Route53は作られない）。

## 2. テンプレート検証

```bash
aws cloudformation validate-template \
  --template-body file://templates/aws-webapp-infra-lab.yaml
```

## 3. スタック作成

```bash
aws cloudformation deploy \
  --template-file templates/aws-webapp-infra-lab.yaml \
  --stack-name aws-webapp-infra-lab \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides $(cat parameters/study.env)
```

> `CAPABILITY_NAMED_IAM` は、名前付きIAMロール（sample-role-web）を作るために必要。

## 4. 出力値の確認

```bash
aws cloudformation describe-stacks \
  --stack-name aws-webapp-infra-lab \
  --query "Stacks[0].Outputs" --output table
```

`BastionPublicIp`、`AlbDnsName`、`DbEndpoint`、`ImageBucketName`、`RedisEndpoint`、
`DbMasterSecretArn` などが得られる。

## 5. アプリ導入に必要な値をSSMから取得

```bash
PROJECT=sample

aws ssm get-parameter --name /$PROJECT/rds/endpoint --query Parameter.Value --output text
aws ssm get-parameter --name /$PROJECT/s3/image-bucket --query Parameter.Value --output text
aws ssm get-parameter --name /$PROJECT/elasticache/endpoint --query Parameter.Value --output text

# RDSパスワード（Secrets Manager管理）
SECRET_ARN=$(aws ssm get-parameter --name /$PROJECT/rds/master-secret-arn --query Parameter.Value --output text)
aws secretsmanager get-secret-value --secret-id "$SECRET_ARN" --query SecretString --output text
# → JSONの "password" がマスター(admin)のパスワード
```

## 6. RDSにアプリ用DB/ユーザーを作成

bastion に SSH して、マスターユーザーで `sample_app` DB と専用ユーザーを作る。

```bash
# 手元PCから踏み台へ
ssh -i path/to/sample-key.pem ec2-user@<BastionPublicIp>

# 踏み台からRDSへ（SQLは scripts/db/create-sample-app-db.sql を用意して流す）
mysql -u admin -p -h db.home < create-sample-app-db.sql
```

## 7. Webサーバーへアプリ導入（web01 → web02）

各Webサーバーで scripts/web/ を順に実行する。SSH接続は `setup-notes.md` を参照。

```bash
# 踏み台経由でWebへ
ssh web01

# ---- ここから web01 上 ----
# 01-02 は ec2-user（sudo）
bash 01-install-middleware.sh
bash 02-create-deploy-user.sh

# 03 以降は deploy
sudo su - deploy
bash 03-install-ruby.sh
source ~/.bash_profile

# 05（環境変数）を先に：exampleをコピーして実値を埋めて実行
cp 05-configure-env.sh.example 05-configure-env.sh
vi 05-configure-env.sh        # SSM/Secrets Managerから取得した値を埋める
bash 05-configure-env.sh
source ~/.bash_profile

# 04（アプリ取得・bundle・precompile）
bash 04-deploy-sample-app.sh

# DBマイグレーション（初回のみ。RDS共有なのでweb01で1回でよい）
cd /var/www/aws-intro-sample-2nd
bundle _1.17.3_ exec rails db:migrate RAILS_ENV=production

# 06（Puma起動）
bash 06-start-puma.sh
```

web02 でも同じ手順を実行する。ただし **db:migrate は不要**（RDS共有のため）。
`SECRET_KEY_BASE` は web01 と同じ値にすること。

## 8. ALBに登録して動作確認

`06-start-puma.sh` の最後で `curl -I http://localhost:3000/assets/...css` が
**200 OK** になっていることを確認してから、ALBターゲットグループにWebを登録する
（CloudFormationで既に登録済みだが、unhealthyなら起動状態を確認）。

ターゲットグループで web01 / web02 が **healthy** になればOK。
`AlbDnsName`（またはドメイン）にブラウザでアクセスして、CSSが当たった画面を確認する。

## 9. 削除

`cost-cleanup.md` を参照。
