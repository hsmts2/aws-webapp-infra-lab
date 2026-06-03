# deployment.md

本ドキュメントでは、CloudFormationによるインフラ作成、SSH接続設定、サンプルアプリ導入、SES設定、動作確認、削除までの一連の手順を整理します。
構成の説明や書籍との差分は [architecture.md](architecture.md) に記載しています。

<br>

## 1. 事前準備

CloudFormationを実行する前に、以下を準備します。

| 項目 | 内容 |
|---|---|
| AWS CLI | インストール済みであること |
| AWS認証情報 | `aws configure` などで設定済みであること |
| EC2キーペア | 事前に作成済みであること |
| グローバルIP | 踏み台サーバーへのSSH許可元として使用 |
| Route 53パブリックホストゾーン | 独自ドメインを使用する場合のみ必要 |
| GitHubリポジトリ | 本リポジトリを作成済みであること |

AWS CLIのバージョンを確認します。

```bash
aws --version
````

認証情報を確認します。

```bash
aws sts get-caller-identity
```

<br>

## 2. パラメータファイルの準備

デプロイ用のパラメータファイルを作成します。

```bash
cp parameters/study.example.env parameters/study.env
vi parameters/study.env
```

`parameters/study.env` には、自分の環境に合わせた値を設定します。

例です。

```text
ProjectName=sample
KeyName=sample-key
YourIpCidr=xxx.xxx.xxx.xxx/32
DomainName=zexample.com
PublicHostedZoneId=Zxxxxxxxxxxxxxxxxxxxx
AlbTargetPort=3000
S3AccessMode=LeastPrivilege
```

独自ドメインを使用しない場合は、`DomainName` と `PublicHostedZoneId` を空のままにします。

```text
DomainName=
PublicHostedZoneId=
```

この場合、ACM証明書、HTTPSリスナー、公開Route 53レコードは作成されません。

`parameters/study.env` は実環境の値を含むため、Git管理対象外にします。

<br>

## 3. CloudFormationテンプレートの検証

CloudFormationテンプレートの構文を確認します。

```bash
aws cloudformation validate-template \
  --template-body file://templates/aws-webapp-infra-lab.yaml
```

エラーが表示されなければ、テンプレートの基本的な構文は問題ありません。

<br>

## 4. CloudFormationスタックの作成

パラメータファイルを読み込み、CloudFormationスタックを作成します。

```bash
PARAMS=$(grep -v '^#' parameters/study.env | xargs)

aws cloudformation deploy \
  --template-file templates/aws-webapp-infra-lab.yaml \
  --stack-name aws-webapp-infra-lab \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides $PARAMS
```

`CAPABILITY_NAMED_IAM` は、名前付きIAMロールを作成するために必要です。

このテンプレートでは、Webサーバー用のIAMロールなどを作成します。

<br>

## 5. スタック出力値の確認

スタック作成後、CloudFormationのOutputsを確認します。

```bash
aws cloudformation describe-stacks \
  --stack-name aws-webapp-infra-lab \
  --query "Stacks[0].Outputs" \
  --output table
```

主な出力値は以下です。

| Output            | 内容                       |
| ----------------- | ------------------------ |
| `AlbDnsName`      | ALBのDNS名                 |
| `WebsiteUrl`      | アプリケーションアクセス用URL         |
| `BastionPublicIp` | 踏み台サーバーのパブリックIP          |
| `Web01PrivateIp`  | web01のプライベートIP           |
| `Web02PrivateIp`  | web02のプライベートIP           |
| `DbEndpoint`      | RDSエンドポイント               |
| `ImageBucketName` | 画像アップロード用S3バケット名         |
| `RedisEndpoint`   | ElastiCache Redisエンドポイント |

<br>

## 6. SSM Parameter Storeから主要値を取得する

アプリケーション設定で使用する値は、Systems Manager Parameter Storeから取得できます。

```bash
PROJECT=sample

aws ssm get-parameter \
  --name /$PROJECT/rds/endpoint \
  --query Parameter.Value \
  --output text

aws ssm get-parameter \
  --name /$PROJECT/s3/image-bucket \
  --query Parameter.Value \
  --output text

aws ssm get-parameter \
  --name /$PROJECT/elasticache/endpoint \
  --query Parameter.Value \
  --output text

aws ssm get-parameter \
  --name /$PROJECT/alb/dns-name \
  --query Parameter.Value \
  --output text
```

RDSマスターユーザーの認証情報はSecrets Managerで管理しています。
Secret ARNはParameter Storeから取得できます。

```bash
SECRET_ARN=$(aws ssm get-parameter \
  --name /$PROJECT/rds/master-secret-arn \
  --query Parameter.Value \
  --output text)

aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ARN" \
  --query SecretString \
  --output text
```

出力されるJSONの `username` と `password` が、RDSマスターユーザーの認証情報です。

注意点として、Secrets Managerで管理しているのはRDSマスターユーザーの認証情報です。
アプリケーションが使用する `sample_app` ユーザーのパスワードは、後続のDB初期化時に自分で設定する値です。

<br>

## 7. SSH設定

手元PCのSSH設定ファイルに、踏み台サーバーとWebサーバーへの接続設定を追加します。

Linux / macOSの場合は以下です。

```text
~/.ssh/config
```

Windowsの場合は以下です。

```text
C:\Users\<ユーザー名>\.ssh\config
```

設定例です。

```sshconfig
Host bastion
    HostName <BastionPublicIp>
    User ec2-user
    IdentityFile ~/.ssh/sample-key.pem

Host web01
    HostName web01.home
    User ec2-user
    IdentityFile ~/.ssh/sample-key.pem
    ProxyJump bastion

Host web02
    HostName web02.home
    User ec2-user
    IdentityFile ~/.ssh/sample-key.pem
    ProxyJump bastion
```

`<BastionPublicIp>` は、CloudFormation Outputsの `BastionPublicIp` に置き換えます。

設定後、踏み台サーバーへ接続します。

```bash
ssh bastion
```

web01へ接続します。

```bash
ssh web01
```

web02へ接続します。

```bash
ssh web02
```

`web01.home` / `web02.home` はVPC内のプライベートDNSです。
ProxyJumpで踏み台サーバーを経由することで、プライベートサブネット上のWebサーバーへ接続します。

<br>

## 8. Webサーバー上でリポジトリを取得する

web01 / web02では、本リポジトリ内の手順書と補助スクリプトを参照して作業します。

まず、web01へ接続します。

```bash
ssh web01
```

web01上でリポジトリを取得します。

```bash
cd ~
git clone https://github.com/<your-account>/aws-webapp-infra-lab.git
cd aws-webapp-infra-lab
```

`<your-account>` は、自分のGitHubアカウント名に置き換えます。

web02でも同様に、リポジトリを取得します。

```bash
ssh web02

cd ~
git clone https://github.com/<your-account>/aws-webapp-infra-lab.git
cd aws-webapp-infra-lab
```

以降のアプリケーション導入では、`docs/deployment.md` と必要に応じて `scripts/` 配下の補助スクリプトを参照します。

<br>

## 9. RDSにアプリ用DBとユーザーを作成する

RDSはPrivateサブネットに配置しており、セキュリティグループではWebサーバーからのMySQL接続を許可しています。
そのため、アプリケーション用DBとユーザーの作成は、踏み台サーバーではなく `web01` から実行します。

web01へ接続します。

```bash
ssh web01
```

MySQLクライアントが未インストールの場合は、以下を実行します。

```bash
sudo yum install -y mysql
```

RDSのマスターユーザーで接続します。

```bash
mysql -u admin -p -h db.home
```

接続後、アプリケーション用のデータベースとユーザーを作成します。

```sql
CREATE DATABASE sample_app;

CREATE USER 'sample_app'@'%' IDENTIFIED BY '任意のパスワード';

GRANT ALL PRIVILEGES ON sample_app.* TO 'sample_app'@'%';

FLUSH PRIVILEGES;
```

この作業はRDSに対して1回だけ実行します。
RDSはweb01とweb02で共有するため、web02で同じSQLを再実行する必要はありません。

作成した `sample_app` ユーザーのパスワードは、後続のアプリケーション環境変数 `AWS_INTRO_SAMPLE_DATABASE_PASSWORD` に設定します。

<br>

## 10. Webサーバーへサンプルアプリを導入する

サンプルアプリは、web01とweb02の両方へ導入します。

基本的な流れは以下です。

```text
1. OSパッケージをインストールする
2. deployユーザーを作成する
3. rbenv / Ruby 2.7.8 をインストールする
4. サンプルアプリを取得する
5. Bundler 1.17.3 をインストールする
6. Gem依存関係を解決する
7. 環境変数を設定する
8. assets:precompile を実行する
9. Pumaを3000番ポートで起動する
```

確定した構成では、ALBからPumaへHTTP:3000で直接転送します。

```text
ALB
  ↓ HTTP:3000
Puma / Rails
```

そのため、Pumaは以下のように `0.0.0.0:3000` で起動します。

```bash
cd /var/www/aws-intro-sample-2nd

nohup bundle _1.17.3_ exec rails server \
  -e production \
  -b 0.0.0.0 \
  -p 3000 \
  > log/puma.log 2>&1 &
```

web01で `SECRET_KEY_BASE` を生成した場合、web02では同じ値を使用します。
web01とweb02で `SECRET_KEY_BASE` が異なると、ALBで振り分けられた際にセッションが維持できない可能性があります。

<br>

## 11. アプリケーション環境変数を設定する

サンプルアプリでは、RDS、S3、ElastiCache、SESなどの接続情報を環境変数で設定します。

`deploy` ユーザーの `.bash_profile` に以下のような値を設定します。

```bash
# Rails
export RAILS_ENV=production
export RAILS_SERVE_STATIC_FILES=1
export RAILS_LOG_TO_STDOUT=1
export SECRET_KEY_BASE='web01とweb02で同じ値'

# RDS
export AWS_INTRO_SAMPLE_DATABASE_PASSWORD='sample_appユーザーのパスワード'

# S3
export AWS_INTRO_SAMPLE_S3_HOST='s3-ap-northeast-1.amazonaws.com'
export AWS_INTRO_SAMPLE_S3_REGION='ap-northeast-1'
export AWS_INTRO_SAMPLE_S3_BUCKET='画像アップロード用S3バケット名'

# ElastiCache Redis
export AWS_INTRO_SAMPLE_REDIS_ADDRESS='redis://Redisエンドポイント:6379/0'

# Application Host
export AWS_INTRO_SAMPLE_HOST='www.zexample.com'

# SES SMTP
export AWS_INTRO_SAMPLE_SMTP_DOMAIN='zexample.com'
export AWS_INTRO_SAMPLE_SMTP_ADDRESS='email-smtp.ap-northeast-1.amazonaws.com'
export AWS_INTRO_SAMPLE_SMTP_USERNAME='SES SMTP Username'
export AWS_INTRO_SAMPLE_SMTP_PASSWORD='SES SMTP Password'
```

設定後、反映します。

```bash
source ~/.bash_profile
```

重要な値が設定されているか確認します。

```bash
echo $RAILS_ENV
echo $RAILS_SERVE_STATIC_FILES
echo $AWS_INTRO_SAMPLE_HOST
env | grep AWS_INTRO_SAMPLE
```

`RAILS_SERVE_STATIC_FILES=1` は、ALBからPumaへ直接転送する構成では重要です。
この値が未設定の場合、CSSなどの静的ファイルが配信されません。

`AWS_INTRO_SAMPLE_HOST` は、ユーザー登録時の有効化メールに含まれるURL生成で使用します。
未設定の場合、ユーザー登録は成功しても、有効化メール送信時にエラーが発生する可能性があります。

<br>

## 12. DBマイグレーションを実行する

DBマイグレーションは、RDSに対して1回だけ実行します。

web01で以下を実行します。

```bash
sudo su - deploy

cd /var/www/aws-intro-sample-2nd

bundle _1.17.3_ exec rails db:migrate RAILS_ENV=production
```

RDSはweb01とweb02で共有するため、web02で同じマイグレーションを再実行する必要はありません。

<br>

## 13. 静的ファイルをプリコンパイルする

web01 / web02の両方で、assetsのプリコンパイルを実行します。

```bash
sudo su - deploy

cd /var/www/aws-intro-sample-2nd

bundle _1.17.3_ exec rails assets:precompile RAILS_ENV=production
```

`Yarn executable was not detected` が表示される場合があります。
ただし、`public/assets` 配下に `application-*.css` や `application-*.js` が出力されていれば、次の手順に進めます。

<br>

## 14. Pumaを起動する

web01 / web02の両方で、Pumaをバックグラウンド起動します。

```bash
sudo su - deploy

cd /var/www/aws-intro-sample-2nd

nohup bundle _1.17.3_ exec rails server \
  -e production \
  -b 0.0.0.0 \
  -p 3000 \
  > log/puma.log 2>&1 &
```

起動状態を確認します。

```bash
ps aux | grep puma | grep -v grep
```

ログを確認します。

```bash
tail -30 log/puma.log
```

`Listening on tcp://0.0.0.0:3000` が表示されていれば、Pumaは3000番ポートで待ち受けています。

<br>

## 15. 動作確認

まず、Webサーバー上でPumaへ直接アクセスします。

```bash
curl -I http://localhost:3000/
```

次に、CSSが配信されるか確認します。

```bash
curl -I http://localhost:3000/assets/$(ls public/assets/ | grep '^application-.*\.css$' | head -1)
```

`HTTP/1.1 200 OK` かつ `Content-Type: text/css` が返れば、Railsから静的ファイルが配信できています。

ALBターゲットグループで、web01 / web02 が `healthy` になっていることを確認します。

最後にブラウザで以下へアクセスします。

```text
https://www.zexample.com
```

または、ドメインを使用しない場合は、CloudFormation Outputsの `WebsiteUrl` または `AlbDnsName` にアクセスします。

Bootstrapが適用された画面が表示されれば、ALBからPumaへの転送と静的ファイル配信は正常です。

<br>

## 16. SES設定

Amazon SESはCloudFormationでは作成しません。
本番アクセス申請、SMTP認証情報の作成、ドメイン検証など、手動対応が必要なためです。

基本的な流れは以下です。

```text
1. SESでドメインを検証する
2. DKIM / 検証用DNSレコードをRoute 53へ登録する
3. 必要に応じて本番アクセスを申請する
4. SMTP認証情報を作成する
5. SMTP Username / SMTP Password を安全な場所へ保存する
6. アプリケーションの環境変数へ設定する
```

アプリケーション側では、以下の環境変数を設定します。

```bash
export AWS_INTRO_SAMPLE_SMTP_DOMAIN='zexample.com'
export AWS_INTRO_SAMPLE_SMTP_ADDRESS='email-smtp.ap-northeast-1.amazonaws.com'
export AWS_INTRO_SAMPLE_SMTP_USERNAME='SES SMTP Username'
export AWS_INTRO_SAMPLE_SMTP_PASSWORD='SES SMTP Password'
export AWS_INTRO_SAMPLE_HOST='www.zexample.com'
```

注意点として、SES SMTP認証情報は作成時にのみCSVで保存できます。
GitHub、スクリーンショット、作業ログには認証情報を残さないでください。

<br>

## 17. 構築時の主なエラーと対応

サンプルアプリ導入時に発生しやすいエラーと対応を整理します。

|  # | 症状                                                    | 原因                                                       | 対応                                                               |
| -: | ----------------------------------------------------- | -------------------------------------------------------- | ---------------------------------------------------------------- |
|  1 | bundler / nokogiriで `Ruby >= 3.2` の互換性エラーが発生する        | Ruby 2.6.6が古い                                            | Ruby 2.7.8を使用する                                                  |
|  2 | `Could not find bundler (1.17.3)` が表示される              | Bundlerのバージョン不一致                                         | `gem install bundler -v 1.17.3` を実行し、以降は `bundle _1.17.3_` を使用する |
|  3 | nokogiriで `conflicting types for canonicalize` が表示される | 新しいglibcとの関数名衝突                                          | nokogiri 1.11.7のプリコンパイル版を入れ、`bundle update nokogiri` を実行する       |
|  4 | `The "libcurl" package isn't available` が表示される        | `fog` が依存する `ovirt-engine-sdk` のビルドに `libcurl-devel` が必要 | `sudo yum install -y libcurl-devel` を実行する                        |
|  5 | `Yarn executable was not detected` が表示される             | Yarnが未導入                                                 | 警告として扱う。assetsが出力されていれば進めてよい                                     |
|  6 | CSSが404または502になる                                      | Puma停止、または静的ファイル配信設定不足                                   | Pumaを `nohup ... &` で起動し、`RAILS_SERVE_STATIC_FILES=1` を設定する      |
|  7 | `RAILS_SERVE_STATIC_FILES` を設定しても反映されない               | `.bash_profile` が読み込まれていない                               | `source ~/.bash_profile` を実行する。必要に応じて起動コマンドの先頭に環境変数を付与する         |
|  8 | ユーザー登録は成功するが有効化メールが送信されない                             | `AWS_INTRO_SAMPLE_HOST` が未設定で、メール本文のURL生成に失敗している         | `AWS_INTRO_SAMPLE_HOST='www.zexample.com'` を設定してPumaを再起動する       |
|  9 | `Account not activated` が表示される                        | メール内の有効化リンクを未クリック                                        | メール内リンクで有効化する。検証を先に進める場合はDBで `activated=1` に更新する                 |

<br>

## 18. nokogiriビルドエラーの対応

書籍指定の nokogiri 1.10.10 を現行環境でソースビルドすると、新しいglibcの `canonicalize` 関数と名前衝突してコンパイルに失敗する場合があります。

```text
error: conflicting types for 'canonicalize'
```

この場合、nokogiri 1.11.7 のプリコンパイル版をインストールしてから、Bundlerで依存関係を更新します。

```bash
gem install nokogiri -v 1.11.7

bundle _1.17.3_ update nokogiri
```

採用しなかった回避策は以下です。

| 回避策                           | 採用しなかった理由                   |
| ----------------------------- | --------------------------- |
| `--platform x86_64-linux`     | 最終的にソースビルドへ進み、同じエラーが発生したため  |
| `CFLAGS="-Dcanonicalize=..."` | glibc側まで影響し、別のビルドエラーにつながるため |

<br>

## 19. CSSが配信されない場合の確認

ALBがPumaへ直接転送しているため、Nginxは静的ファイル配信の経路に入りません。
Rails自身がCSSを配信するため、`RAILS_SERVE_STATIC_FILES=1` が必要です。

まず、Puma直のCSS配信を確認します。

```bash
curl -I http://localhost:3000/assets/$(ls public/assets/ | grep '^application-.*\.css$' | head -1)
```

結果ごとの確認ポイントです。

| 結果                    | 意味                       | 対応                                           |
| --------------------- | ------------------------ | -------------------------------------------- |
| `Couldn't connect`    | Pumaが停止している              | Pumaを起動する                                    |
| `404`                 | Pumaは起動しているが、静的ファイル配信が無効 | `RAILS_SERVE_STATIC_FILES=1` を設定してPumaを再起動する |
| `200 OK` / `text/css` | 正常                       | ALBターゲット登録とブラウザキャッシュを確認する                    |

<br>

## 20. 有効化メールが送信されない場合の確認

ユーザー登録は成功しているのに有効化メールが送信されない場合、`AWS_INTRO_SAMPLE_HOST` が未設定の可能性があります。

`AWS_INTRO_SAMPLE_HOST` は、メール本文に含める有効化リンクのURL生成で使用します。

```bash
export AWS_INTRO_SAMPLE_HOST='www.zexample.com'
```

Pumaログを確認しながら、未使用のメールアドレスでユーザー登録します。

```bash
cd /var/www/aws-intro-sample-2nd
tail -f log/puma.log
```

ログに以下のような内容が出れば、アプリケーションからSESへの送信処理は成功しています。

```text
Sent mail to xxxxx@example.com
```

送信ログが出ているのにメールが届かない場合は、迷惑メールフォルダやSES側の設定を確認します。

検証を先に進めたい場合は、DBでユーザーを手動有効化できます。

```sql
UPDATE users
SET activated = 1, activated_at = NOW()
WHERE email = '登録したメールアドレス';
```

<br>

## 21. Pumaの停止・再起動

Pumaを停止する場合は、PIDファイルを使います。

```bash
kill $(cat /var/www/aws-intro-sample-2nd/tmp/pids/server.pid)
```

プロセスが停止したか確認します。

```bash
ps aux | grep puma | grep -v grep
```

再起動します。

```bash
cd /var/www/aws-intro-sample-2nd

nohup bundle _1.17.3_ exec rails server \
  -e production \
  -b 0.0.0.0 \
  -p 3000 \
  > log/puma.log 2>&1 &
```

`A server is already running` が表示される場合は、Pumaがすでに起動している可能性があります。
既存プロセスを確認してから、必要に応じて停止・再起動します。

<br>

## 22. コスト管理と削除

学習用スタックには、継続課金が発生するリソースが含まれます。

特に以下のリソースは料金が大きくなりやすいため、学習完了後は必ず確認します。

| 優先度 | リソース        | 理由                           |
| --: | ----------- | ---------------------------- |
|   高 | NAT Gateway | 時間課金とデータ処理課金が発生するため          |
|   高 | ElastiCache | ノード数に応じて課金されるため              |
|   高 | RDS         | DBインスタンスの稼働時間に応じて課金されるため     |
|   中 | ALB         | 稼働時間とLCUで課金されるため             |
|   中 | EIP         | 未関連付けのEIPは課金対象となるため          |
|   中 | S3          | バケット保持やオブジェクト保存容量に応じて課金されるため |

<br>

## 23. CloudFormationスタックの削除

学習が完了したら、CloudFormationスタックを削除します。

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

## 24. 削除後に確認するリソース

CloudFormationスタック削除後も、保持設定や手動作成により一部リソースが残る場合があります。

| リソース                | 確認内容                                    |
| ------------------- | --------------------------------------- |
| RDSスナップショット         | `DeletionPolicy: Snapshot` により残る場合があります |
| S3バケット              | `DeletionPolicy: Retain` により残る場合があります   |
| S3オブジェクト            | バケット削除前に空にする必要があります                     |
| EIP                 | 未関連付けのEIPが残っていないか確認します                  |
| NAT Gateway         | 削除漏れがないか確認します                           |
| ElastiCache         | クラスター削除が完了しているか確認します                    |
| Secrets Manager     | 削除保留期間が設定されている場合があります                   |
| Route 53パブリックホストゾーン | 手動作成したHosted Zoneは残ります                  |
| SES SMTP認証情報        | 不要になったIAMユーザーまたはアクセスキーを削除します            |

<br>

## 25. セキュリティ後始末

学習完了後は、不要な認証情報を削除します。

* SES SMTP用IAMユーザーまたはアクセスキーを無効化・削除します。
* 作業ログやスクリーンショットに認証情報が含まれていないか確認します。
* `SECRET_KEY_BASE` やSMTP認証情報を公開リポジトリに含めないよう確認します。
* `parameters/study.env` など、実環境の値を含むファイルがGit管理対象になっていないか確認します。

<br>
```
